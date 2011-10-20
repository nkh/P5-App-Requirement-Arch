
=pod

 perl ir_done.pl IRS_2008-06-09.txt Requirements/Formatted/

this will generate a list of the requirements that refer to irs and a short statistic

=cut

use strict ;
use warnings ;

use Data::TreeDumper ;

$|++ ;

use lib qw(. scripts/lib) ;
use requirements ;

my $master_template = 'master_template.txt' ;

my $source_file = shift @ARGV ;
my %source_irs ;

open my $source_fh, $source_file or die $@ ;

while(<$source_fh>)
	{
	if(/\*\*\* IR: (\d+)/)
		{
		$source_irs{$1}++ ;
		}
	}

my $number_of_input_irs = scalar(keys %source_irs) ;

my  ($requirements_structure, $requirements, $categories, $ok_parsed, $errors) = get_requirements_structure(\@ARGV, $master_template) ;

my %requirements_keeping_ir ;

while ((my $requirement_name, my $requirement) = each %{$requirements})
	{
	if(exists $requirement->{DEFINITION})
		{
		for my $origin (@{$requirement->{DEFINITION}{ORIGINS}})
			{
			if($origin =~ /ir (\d+)/i)
				{
				#~ print "Found origin '$origin' for '$requirement_name'\n" ;
				push @{$requirements_keeping_ir{$requirement_name}{ORIGIN}},  $origin ;
				delete $source_irs{$1} ; ;
				}
			}
		}
		
	if(exists $requirement->{SUB_REQUIREMENTS})
		{
		for my $sub_requirement (keys %{$requirement->{SUB_REQUIREMENTS}})
			{
			if($sub_requirement =~ /ir (\d+)/i)
				{
				#~ print "Found sub requirement '$sub_requirement' for '$requirement_name'\n" ;
				push @{$requirements_keeping_ir{$requirement_name}{SUB_REQUIREMENTS}},  $sub_requirement ;
				delete $source_irs{$1} ;
				}
			}
		}
	}
	
my $number_of_kept_irs = $number_of_input_irs  - scalar(keys %source_irs) ;

print <<EOT ;
number of input irs   = $number_of_input_irs  
number of kept irs = $number_of_kept_irs

EOT

print DumpTree \%requirements_keeping_ir, 'Requirements refering to IRs' ;

print <<EOT ;

number of input irs   = $number_of_input_irs  
number of kept irs = $number_of_kept_irs

EOT

print "IRs not refered to from requirements:\n" ;

print "\t$_\n" for (sort keys %source_irs) ;
