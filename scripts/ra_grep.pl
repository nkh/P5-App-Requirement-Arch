
#!/usr/bin/perl

use strict ;
use warnings;

use File::Find::Rule ;
use Data::TreeDumper ;
use File::Spec  ;
use Getopt::Long ;

Getopt::Long::Configure('no_auto_abbrev', 'no_ignore_case') ;

main() ;

#----------------------------------------------------------------------------

sub display_help
{
warn <<'EOH' ;

NAME
  ra_grep

SYNOPSIS
  $ ra_grep -L -r -P pattern -P pattern [[path_spec]/[file_spec]] [[path_spec]/[file_spec]] ...

DESCRIPTION
  This utility search for patterns in requirement files and display them. The 
    defalt output looks like the output of the 'tree' utility. When the otion -L
    is given, the output is a list and would look like the result of 
	
	grep -R -l -P -P path/to/requirements
	
[[path_spec]/[file_spec]]

OPTIONS
  --r|recursive		read  all  files under each directory, recursively
  
  -l|list		display list of matching files without tree graph
  
  -p|pattern pattern	match the text of the requirement file to the pattern
			multiple patterns are allowed

  --path		display full path in tree
  
  --s|statistics	display some search statistics
  
  --silent		no display, useful with option --statistics
  
  --h|help		displays this help message
  
Output
  The document is output on STDOUT.
	
AUTHORS
  Khemir Nadim ibn Hamouda.

EOH

exit(1) ;
}

#------------------------------------------------------------------------------------

sub main
{
	
# option handling
my (@patterns, $as_list, $max_depth, $full_path, $silent, $display_statistics) ;

die 'Error parsing options!'unless 
	GetOptions
		(
		'r|recursive' => \$max_depth,
		'p|pattern=s' => \@patterns,
		'l|liat' => \$as_list,
		'path' => \$full_path,
		'silent' => \$silent,
		's|statistics' => \$display_statistics,

		'h|help' => \&display_help, 
		) ;

unless(@patterns)
	{
	warn "Error: no pattern specified!\n" ;
	display_help()
	}

my @sources = @ARGV ;
push @sources , '.' unless @sources ;

$max_depth = defined $max_depth ? 5000 : 0 ;

#-----------------------------------------------------------------------------------------------------------

my (%tree, %tree_directories, @matches, %statistics) ;
	
for my $source (@sources)
	{
	my ($source_directory, $source_file_pattern) = get_directory_and_file_pattern($source);
	push @{$statistics{sources}}, "$source_directory => $source_file_pattern" ;
	
	for my $file_name (File::Find::Rule->maxdepth($max_depth)->file()->name($source_file_pattern)->in( $source_directory))
		{
		#~ print "Checking '$file_name\n";
		$statistics{files_matching_source_pattern}++ ;
		
		my ($volume, $directories, $file) = File::Spec->splitpath($file_name) ;	
		
		if(matches_regexes(\%statistics, $file_name, \@patterns))
			{
			my $tree_position ;
			
			if(defined $tree_directories{$directories} && 'HASH' eq ref $tree_directories{$directories})
				{
				$tree_position = $tree_directories{$directories} ;
				}
			else
				{
				$statistics{directories_matching_source_pattern}++ ;

				$tree_position = \%tree ;
				
				my @dirs = File::Spec->splitdir($directories) ;		
				delete $dirs[-1] ;
			
				for (@dirs)
					{
					$tree_position->{$_} = {} unless exists $tree_position->{$_} ;
					$tree_position = $tree_position->{$_} ;
					}
				}
				
			$tree_directories{$directories} = $tree_position ;
			
			if($as_list)
				{
				push @matches, $file_name ;
				}
			else
				{
				$tree_position->{$file} = $full_path ? $file_name : 1 ;
				}			
			
			$statistics{matching_files}++ ;
			}
		else
			{
			$statistics{non_matching_files}++ ;
			$statistics{directories_matching_source_pattern}++ unless exists $tree_directories{$directories} ;
			$tree_directories{$directories}++ ;
			}
		}
	}

print DumpTree \%statistics, 'Statistics:', DISPLAY_ADDRESS => 0 if $display_statistics;

unless($silent)
	{
	if($as_list)
		{
		print join "\n", @matches ;
		}
	else
		{
		print DumpTree \%tree, 'Matches:', DISPLAY_ADDRESS => 0 ;
		}
	}
	
return ! $statistics{matching_files} ;
}

sub matches_regexes
{
my($statistics, $file_name,  $patterns) = @_ ;

open my $file, '<', $file_name or die "Can't open '$file_name: $!" ;

my $matched = 0 ;

FILE:
while(my $line = <$file>)
	{
	for my $grep (@{$patterns})
		{
		if($line =~ $grep)
			{
			$matched++ ;
			last FILE ;
			}
		}
	}
	
return $matched ;
}

sub get_directory_and_file_pattern
{
my ($source) = @_ ;
my ($source_directory, $source_file_pattern) ;

if($source =~ m[ / ]x)
	{
	($source_directory) = $source =~ m[ (.*) / ]x ;
	($source_file_pattern) = $source =~ m[ .*/ ([^/]+) ]x ;
	}
else
	{
	if (-d $source)
		{
		$source_directory = $source  ;
		}
	else
		{
		$source_file_pattern = $source ;
		}
	}
	
$source_directory = '.' unless defined $source_directory ;
$source_file_pattern = '*.*' unless defined $source_file_pattern ;

return ($source_directory, $source_file_pattern) ;
}
