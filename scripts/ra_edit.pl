#!/usr/bin/env perl

use strict ;
use warnings ;
use Carp ;

use Proc::InvokeEditor ;
use App::Requirement::Arch::Requirements qw(create_requirement check_requirements get_requirements_structure)  ;
use App::Requirement::Arch qw(get_template_files load_master_template load_master_categories) ;
use App::Requirement::Arch::Categories qw(merge_master_categories) ;
use App::Requirement::Arch::Spellcheck qw(spellcheck)  ;

use File::Slurp ;
use File::Basename ;
use Getopt::Long;
use Data::Dumper ;
use Data::TreeDumper ;

use Readonly ;
Readonly my $EMPTY_STRING => q{} ;

#------------------------------------------------------------------------------------------------------------------

sub display_help
{
warn <<'EOH' ;

NAME
	ra_edit

SYNOPSIS

	$ ra_edit path/to/requirement

DESCRIPTION
	This script will open the requirement in a text editor, creating it from templates
	found in ~/.ra/

	On exit the file contents is checked for format validity. Extra checks are available through options
	
ARGUMENTS
  --master_template_file     file containing the master template
  --master_categories_file   file containing the categories template
  --free_form_template       user defined template matching the master template
  --no_check_categories      do not check the requirement categories
  --no_spellcheck            perform no spellchecking
  --no_file_ok               do nothing if no path to requirement is given

FILES
	~/.ra/templates/master_template.pl
	~/.ra/templates/master_categories.pl
	~/.ra/templates/free_form_template.rat

AUTHORS
	Khemir Nadim ibn Hamouda

EOH

exit(1) ;
}

#------------------------------------------------------------------------------------------------------------------

my ($master_template_file, $master_categories_file, $free_form_template) ;
my ($user_dictionary, $no_spellcheck, $raw, $no_check_categories, $no_file_ok) ;

die 'Error parsing options!'unless 
	GetOptions
		(
		'master_template_file=s' => \$master_template_file,
		'master_categories_file=s' => \$master_categories_file,
		'free_form_template=s' => \$free_form_template,
		'user_dictionary=s' => \$user_dictionary,
		'no_spellcheck' => \$no_spellcheck,
		'raw=s' => \$raw,
		'no_check_categories' => \$no_check_categories,
		'no_file_ok' => \$no_file_ok,
		'h|help' => \&display_help, 
		
		'dump_options' => 
			sub 
				{
				print join "\n", map {"-$_"} 
					qw(
					master_template_file
					master_categories_file
					free_form_template
					user_dictionary
					no_spellcheck
					raw
					no_check_categories
					no_file_ok
					help
					) ;
					
				exit(0) ;
				},

		) ;

($master_template_file, $master_categories_file, $free_form_template)  
	= get_template_files($master_template_file, $master_categories_file, $free_form_template)   ;

my @files ;

for my $requirement_file (@ARGV) 
	{
	my $requirement_text = $EMPTY_STRING ;
	my $violations_text = $EMPTY_STRING ;

	if( -e $requirement_file)
		{
		croak "Error: '$requirement_file' is not a file." unless( -f $requirement_file) ;
		croak "Error: '$requirement_file' is not writable." unless( -w $requirement_file) ;
		
		eval
			{
			my $violations 
				= check_requirement_file
					(
					$master_template_file, $master_categories_file, $requirement_file,
					$user_dictionary, $no_spellcheck, $no_check_categories
					) ;
			
			if(exists $violations->{$requirement_file})
				{
				$violations_text = DumpTree($violations->{$requirement_file}, 'Violations:', DISPLAY_ADDRESS => 0) ;
				$violations_text .= "\nDo not modify the violation text above, it will be automatically removed.\n" ;
				$violations_text =~ s/^/# /mg ;
				}
			} ;
		
		if($@)
			{
			$violations_text = "Error parsing the file as a requirement (this message changes the error message line numbers):\n$@\n" ;
			$violations_text .= "\nDo not modify the violation text above, it will be automatically removed.\n" ;
			$violations_text =~ s/^/# /mg ;
			}
		
			
		$requirement_text = $violations_text . read_file($requirement_file) ;
		}
	else
		{
		my ($requirement_name) = File::Basename::fileparse($requirement_file, ('\..*')) ;
		
		#todo: accept raw source
		
		if(defined $free_form_template)
			{
			my $violations 
				= check_requirement_file
					(
					$master_template_file, $master_categories_file, $free_form_template,
					$user_dictionary, $no_spellcheck, $no_check_categories
					) ;
			
			if(exists $violations->{$free_form_template})
				{
				croak DumpTree $violations->{$free_form_template}, "Error: free form template has errors, aborting:" ;
				}
			else
				{
				$requirement_text = read_file($free_form_template) ;
				
				$requirement_text =~ s/'NAME'\s+=>\s'[^']*'/NAME => '$requirement_name'/ ;
				}
			}
		else
			{
			# create requirement from master template

			my $requirement_template = load_master_template($master_template_file)->{REQUIREMENT} ;
			
			my $requirement = create_requirement($requirement_template , {NAME => $requirement_name, ORIGINS =>['']}) ;
			
			$requirement_text = Dumper $requirement ;
			$requirement_text =~ s/\$VAR1 =// ;
			$requirement_text =~ s/^\s*//gm ;
			}
		}

	push @files, [$requirement_file, $requirement_text, $violations_text] ;
	}


eval
	{
	edit_in_vi('-p', $master_categories_file, \@files) ;

	my $solutions = '' ;

	my $solution_index = 0 ;	
	for my $file (@files) 
		{
		my ($requirement_file, $requirement_text, $violations_text, undef, $edited_requirement_text) = @{ $file } ;

		# remove violation message
		$edited_requirement_text =~ s/\Q$violations_text// ;
		
		# save edited requirement
		write_file($requirement_file, $edited_requirement_text) ;

		# check
		print STDERR "===== POST EDIT =====\n\n" ;	

		my $violations = check_requirement_file
				(
				$master_template_file, $master_categories_file, $requirement_file,
				$user_dictionary, $no_spellcheck, $no_check_categories
				) ;
		
		if(exists $violations->{$requirement_file})
			{

			print DumpTree($violations->{$requirement_file}, "Error: Violations in '$requirement_file'", DISPLAY_ADDRESS => 0) ;
			
			print "\n" ;

			for my $error ( @{$violations->{$requirement_file}{errors} })
				{
				$solutions .= ' (' . $solution_index++ . ')  ' . $error->[1] . "\n" if ('ARRAY' eq ref $error) ;
				}
			}
		}

		print $solutions ;
	} ;
	
die $@ if $@ ;


#------------------------------------------------------------------------------------------------------------------

sub check_requirement_file
{
	
my
(
$master_template_file, $master_categories_file, $requirement_file,
$user_dictionary, $no_spellcheck, $no_check_categories
) = @_ ;

my ($files, $ok_parsed, $requirements_with_errors, $violations) 
	= App::Requirement::Arch::Requirements::get_requirements_violations
		($master_template_file, $requirement_file) ;

unless($no_spellcheck)
	{
	my ($file_name_errors, $errors_per_file) = spellcheck($requirement_file, $user_dictionary) ;

	$violations->{$requirement_file}{spellchecking_errors} = $errors_per_file->{$requirement_file} if exists $errors_per_file->{$requirement_file}
	}
	
unless($no_check_categories)
	{
	my $category_structure = load_master_categories($master_categories_file) ;

	my ($requirements_structure, $requirements, $categories, $ok_parsed, $errors)
		= get_requirements_structure($requirement_file, $master_template_file) ;
	
	my ($in_master_only, $in_requirements_only) = merge_master_categories($category_structure, $requirements_structure, '') ;

	for ( grep {$_ ne '/NOT_CATEGORIZED' and $_ ne '/STATISTICS'} sort keys %{$in_requirements_only})
		{
		push @{ $violations->{$requirement_file}{not_in_master_categories}}, $_ ;
		}
	}
	
return $violations ;	
}

use File::Temp qw(tempfile);
File::Temp->safe_level( File::Temp::STANDARD );


sub edit_in_vi 
{
my $options = shift; 
my $master_categories_file = shift; 

my $files = shift ; # list of file_name/strings

my @temporary_files  ;

for my $file (@{ $files }) 
	{
	my ($file_name, $text) = @{ $file } ;

	my ($template) = File::Basename::fileparse($file_name, ('\..*')) ;

	# create a temporary file
	my ($fh, $temporary_file_name) = tempfile($template . '_XXXX' , UNLINK => 1, SUFFIX => '.pl');
	print $fh $text;
	close $fh or die "Couldn't close temporary file [$temporary_file_name]; $!";

	push @temporary_files, $temporary_file_name ;
	push @{ $file }, $temporary_file_name ;
	}

# create a temporary rendering of categories
my ($fh, $master_categories) = tempfile('master_categories_XXXX' , UNLINK => 1);
`/usr/bin/env perl $master_categories_file 1 > $master_categories` ;
`echo '# vi:syntax=no' >> $master_categories` ;
close $fh or die "Couldn't close temporary file [$master_categories]; $!";

# start the editor
my $rc = system 'vi', $options, @temporary_files, $master_categories, $master_categories_file ;

# check what happened - die if it all went wrong.
unless ($rc == 0) 
	{
	my ($exit_value, $signal_num, $dumped_core);
	$exit_value = $? >> 8;
	$signal_num = $? & 127;
	$dumped_core = $? & 128;
	die "Error in editor - exit val = $exit_value, signal = $signal_num, coredump? = $dumped_core: $!";
	}

for my $file (@{ $files }) 
	{
	my ($file_name, $text, $violations, $temp_file_name) = @{ $file } ;

	# read the temp file
	push @{ $file }, join('', read_file($temp_file_name)) ;
	}

return ;
}

