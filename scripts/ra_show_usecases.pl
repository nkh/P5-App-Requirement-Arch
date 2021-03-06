#!/usr/bin/env perl

use strict ;
use warnings ;

use Data::TreeDumper ;


use Getopt::Long;
use File::Slurp;

use App::Requirement::Arch::Requirements qw(get_files_to_check load_requirement) ;
use App::Requirement::Arch qw(get_template_files load_master_template) ;

#------------------------------------------------------------------------------------------------------------------

sub display_help
{
warn <<'EOH' ;

NAME
	ra_show_usecases

SYNOPSIS

	$ perl ra_show_usecases --show_collapsed path/to/use_cases/*

DESCRIPTION
	This script will generated a dhtml document for the use cases.

ARGUMENTS
	--master_template_file   file containing the master template
	
	--show_collapsed         the uses cases display state is collapsed by default
	--show_collapse_button   the uses cases display state is collapsed by default
	--title                  the html title to use, default "Use cases"
	--header_file            a file name which content will be prepended
			           to the generated document

AUTHORS
	Khemir Nadim ibn Hamouda

EOH

exit(1) ;
}

#------------------------------------------------------------------------------------------------------------------

my ($show_collapsed, $show_collapse_button, $html_title, $header_file);
my ($master_template_file, $master_categories_file) ;

die 'Error parsing options!'unless 
	GetOptions
		(
		'master_template_file=s' => \$master_template_file,
		'h|help' => \&display_help, 
		
		'show_collapsed' => \$show_collapsed,
		'show_collapse_button' => \$show_collapse_button,
		'title=s'	 => \$html_title,
		'header_file=s'	 => \$header_file,
		
		'dump_options' => 
			sub 
				{
				print join "\n", map {"-$_"} 
					qw(
					master_template_file
					help
					show_collapsed
					show_collapse_button
					title
					header_file
					) ;
				exit(0) ;
				},
		
		);


@ARGV or die display_help() ;

my %use_cases ;

($master_template_file, $master_categories_file)  = get_template_files($master_template_file, $master_categories_file)   ;
my $master_template = load_master_template($master_template_file) ;

for my $use_case_definition_file (get_files_to_check(\@ARGV))
	{
	my ($use_case) = load_requirement($master_template, $use_case_definition_file) ;
	
	next unless $use_case->{TYPE} eq 'use case' ;

	if(defined $use_case)
		{
		bless $use_case, 'use_case';
		$use_cases{$use_case->{NAME}} = $use_case ;
		$use_case->{ORIGIN_FILE} = $use_case_definition_file ;
		}
	else
		{
		warn "can't parse use case '$use_case_definition_file', $!, $@\n" ;
		}
	}

my $body = '' ;
my $use_case_number = 0 ;

for my $use_case_name (sort keys  %use_cases)
	{
	my $use_case = $use_cases{$use_case_name} ;
	
	$use_case_number++;
	
	if($use_case->{NAME} eq '')
		{
		warn "Skipping '$use_case->{ORIGIN_FILE}', name is empty string!\n" ;
		next ;
		}
		
	if
		(
		exists $use_case->{ABSTRACTION_LEVEL}
		&& $use_case->{ABSTRACTION_LEVEL} eq 'system'
		) 
		{
		warn "*** $use_case->{NAME} ***\n" ;
		$body .= DumpTree
			(
			$use_case,
			$use_case->{NAME},
			RENDERER => 
				{
				NAME => 'DHTML',
				COLLAPSED => $show_collapsed,
				CLASS => "class_$use_case_number", 
				BUTTON =>
					{
					COLLAPSE_EXPAND => $show_collapse_button,
					},
				},
			FILTER => \&use_case_filter,
			FILTER_ARGUMENT =>
				{
				ALL_USE_CASES => \%use_cases,
				LEVEL_0_FILTER =>
					[
					qw(
						DESCRIPTION
						ACTORS_INTERESTS
						PRECONDITIONS
						RELATED_REQUIREMENTS
						STEPS
						DEFINITION
						) 
					],
				}, 

			NO_NO_ELEMENTS => 1,
			DISPLAY_ADDRESS => 0,
			DISPLAY_OBJECT_TYPE => 0,
			) ;
			
		$body .= '<br>' ;
		}
	}

$html_title = "Use cases" unless ($html_title);

my $header = '';
$header = read_file($header_file) if ($header_file);

print <<EOT;
<?xml version="1.0" encoding="iso-8859-1"?>
<!DOCTYPE html 
PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd"
>

<html>
<!-- Automatically generated by Perl and Data::TreeDumper::DHTML -->
<head>
<title>$html_title</title>

</head>
<body>
<p>$header</p>
$body
</body>
</html>
EOT


#------------------------------------------------------------------------------------------------------------------

sub ordered
{
use Tie::IxHash ;
tie my %hash, 'Tie::IxHash' => @_ ;
return \%hash ;
}

#------------------------------------------------------------------------------------------------------------------

sub use_case_filter
{
my ($tree, $level, $path, $nodes_to_display, $setup, $filter_argument) = @_ ;

if('use_case' eq ref $tree)
	{
	return('HASH', undef, grep {defined $tree->{$_}} @{$filter_argument->{LEVEL_0_FILTER}},) ;
	}
else
	{
	if($path =~ /^\{'STEPS/)
		{
		#~ warn "$path\n" ;
		if('HASH' eq ref $tree)
			{
			if($path =~ /\{'HANDLED_IN'\}$/)
				{
				for my $handler (keys %{$tree})
					{
					if(exists $filter_argument->{ALL_USE_CASES}{$handler})
						{
						warn "\tmerging '$handler'\n" ;
						#~ warn "\t\t$_\n"  for(split('\{', $path)) ;
						
						use Storable qw(dclone);
						$tree->{$handler}{DEFINITION} = dclone($filter_argument->{ALL_USE_CASES}{$handler}) ;
						}
					else
						{
						warn "\tCan't find sub use case '$handler'!\n" ;
						}
					}
				}
				
			return('HASH', undef, grep {defined $tree->{$_}} keys %{$tree}) ;
			}
		else
			{
			return(Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
			}
		}
	else
		{
		return(Data::TreeDumper::DefaultNodesToDisplay($tree)) ;
		}
	}
}


