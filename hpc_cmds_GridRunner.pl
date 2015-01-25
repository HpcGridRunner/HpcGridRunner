#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib ("$FindBin::Bin/PerlLib");
use HPC::GridRunner;
use List::Util qw (shuffle);

use Getopt::Long qw(:config no_ignore_case bundling);

my $usage = <<_EOUSAGE_;

################################################################
# Required:
#
#  -c <string>        file containing list of commands
#  --grid_conf|G <string>   grid config file
#
# Optional:
#  
#  --parafly          if any grid commands fail on the grid, try rerunning
#                     them locally using ParaFly (second chance to succeed).
#                     This requires that ParaFly be installed and in your PATH
#                     Get ParaFly here: http://parafly.sourceforge.net/
#
####################################################################


_EOUSAGE_

	;


my $grid_conf_file;
my $cmd_file;
my $help_flag;
my $parafly_flag = 0;

&GetOptions ( 'h' => \$help_flag,
			  'c=s' => \$cmd_file,
		
              'grid_conf|G=s' => \$grid_conf_file,
             
              'parafly' => \$parafly_flag,

              );


unless ($cmd_file && $grid_conf_file) { 
	die $usage;
}

if ($help_flag) {
	die $usage;
}

if ($parafly_flag) {
    &HPC::GridRunner::use_parafly();
}


main: {

	my $uname = `uname -n`;
	chomp $uname;

	print "SERVER: $uname, PID: $$\n";
	
    
    open (my $fh, $cmd_file) or die "Error, cannot open $cmd_file";
    my @cmds;

    while (<$fh>) {
        chomp;
        if (/\w/) {
            push (@cmds, $_);
        }
    }
    close $fh;

    @cmds = shuffle @cmds;  ## to even out load on grid nodes.  Some may topload their jobs!

    my $cache_file = "$cmd_file.hpc-cache_success";
    
    my $grid_runner = new HPC::GridRunner($grid_conf_file, $cache_file);
    my $ret = $grid_runner->run_on_grid(@cmds);
    
    if ($ret) {
        
        print STDERR "Error, not all commands could complete successfully... cannot continue.";
        
        exit(1);
    }
    else {
        ## all good
        exit(0);
    }
}


    
