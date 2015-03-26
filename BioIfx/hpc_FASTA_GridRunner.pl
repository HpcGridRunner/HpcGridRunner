#!/usr/bin/env perl

use strict;
use FindBin;
use lib ("$FindBin::Bin/../PerlLib");
use Fasta_reader;
use Getopt::Long qw(:config posix_default no_ignore_case bundling pass_through);
use strict;
use Carp;
use Cwd;
use HPC::GridRunner;
use List::Util qw (shuffle);
use File::Basename;


my $usage =  <<_EOH_;

#######################################################################################################################
#
# Required:
#
#   --query_fasta|Q <string>       query multiFastaFile (full or relative path)
#
#   --cmd_template|T <string>      program command line template:   eg. "/path/to/prog [opts] __QUERY_FILE__ [other opts]"
#
#   --seqs_per_bin|N <int>         number of sequences per partition.
# 
#   --out_dir|O <string>           output directory 
#
#  And:
#
#      --grid_conf|G <string>          grid config file (see hpc_conf/ for examples)
#   Or
#      --parafly_only <int>             run locally using ParaFly (set to number of parallel processes)
#
# Optional:
#
#   --prep_only|X                  partion data and create cmds list, but don't launch on the grid.
#
#   --parafly                      use parafly to re-exec previously failed grid commands (use with --grid_conf)
#   
#
########################################################################################################################


_EOH_

    
    ;

my $query_fasta_file;
my $program_cmd_template;
my $bin_size;
my $help = 0;
my $CMDS_ONLY = 0;
my $out_dir;
my $prep_only_flag = 0;
my $grid_conf_file;
my $parafly_only = 0;
my $parafly_flag = 0;


&GetOptions('query_fasta|Q=s' => \$query_fasta_file,
            'cmd_template|T=s' => \$program_cmd_template,
            'seqs_per_bin|N=i' => \$bin_size,
            'out_dir|O=s' => \$out_dir,
            'prep_only|X' => \$prep_only_flag,
            'grid_conf|G=s' => \$grid_conf_file,
            
            'parafly_only=i' => \$parafly_only,
            'parafly' => \$parafly_flag,
            'help|h' => \$help,

    );



if ($help) {
    die $usage;
}

unless ($query_fasta_file && $program_cmd_template && $bin_size && $out_dir && ($parafly_only || $grid_conf_file) ) {
    die $usage;
}

unless ($query_fasta_file =~ /^\//) {
    $query_fasta_file = cwd() . "/$query_fasta_file";
}


unless ($program_cmd_template =~ /__QUERY_FILE__/) {
    die "Error, program cmd template must include '__QUERY_FILE__' placeholder in the command";
}


if ($parafly_flag) {
    &HPC::GridRunner::use_parafly();
}


## Create files to search

my $fastaReader = new Fasta_reader($query_fasta_file);


my $curr_dir = cwd;

my @searchFileList;

my $count = 0;
my $current_bin = 1;

unless ($out_dir =~ m|^/|) {
    # provide full path
    $out_dir = "$curr_dir/$out_dir";
}

mkdir $out_dir or die "Error, cannot mkdir $out_dir";

my $bindir = "$out_dir/grp_" . sprintf ("%04d", $current_bin);
mkdir ($bindir) or die "Error, cannot mkdir $bindir";

my $ParaFlyProg = "";
if ($parafly_only) {
    $ParaFlyProg = `which ParaFly`;
    unless ($ParaFlyProg =~ /\w/) {
        die "Error, cannot find ParaFly program. Be sure it's in your PATH setting. \n";
    }
    chomp $ParaFlyProg;
}

while (my $fastaSet = &get_next_fasta_entries($fastaReader, $bin_size) ) {
    
	$count++;
	
    my $filename = "$bindir/$count.fa";
                
    push (@searchFileList, $filename);
	
    open (TMP, ">$filename") or die "Can't create file ($filename)\n";
    print TMP $fastaSet;
    close TMP;
    chmod (0666, $filename);
    	
	if ($count % $bin_size == 0) {
		# make a new bin:
		$current_bin++;
		$bindir = "$out_dir/grp_" . sprintf ("%04d", $current_bin);
		mkdir ($bindir) or die "Error, cannot mkdir $bindir";
	}
}

print STDERR "Sequences to search: @searchFileList\n";
my $numFiles = @searchFileList;
print STDERR "There are $numFiles jobs to run.\n";


if  ($numFiles) {
    
    my @cmds;
    ## formulate blast commands:
    foreach my $searchFile (@searchFileList) {
                
        my $cmd = $program_cmd_template;
        $cmd =~ s/__QUERY_FILE__/$searchFile/g;
        

        $cmd .= " > $searchFile.OUT ";
		
        unless ($CMDS_ONLY) {
			$cmd .= " 2>$searchFile.ERR";
		}
        push (@cmds, $cmd);
    }
    
	
    @cmds = shuffle(@cmds);

    my $cmd_file = "$out_dir.cmds";

	open (my $fh, ">$cmd_file") or die $!;
	foreach my $cmd (@cmds) {
		print $fh "$cmd\n";
	}
	close $fh;
	
    if ($prep_only_flag) {
        print STDERR "\n\n\t** CMDS written to file: $cmd_file, stopping here due to --prep_only flag being set.\n\n";
        exit(0);
    }


    if ($parafly_only) {

        my $cmd = "$ParaFlyProg -c $cmd_file -CPU $parafly_only -shuffle -v";
        my $ret = system($cmd);
        if ($ret) {
            die "Error, cmd: $cmd died with ret $ret";
        }
        exit(0); # successe
        

    }
    else {
    
        
        my $cache_file = "$cmd_file.hpc-cache_success";
        
        my $grid_runner = new HPC::GridRunner($grid_conf_file, $cache_file);
        my $ret = $grid_runner->run_on_grid(@cmds);
        
        if ($ret) {
            
            print STDERR "Error, not all commands could complete successfully...\n\n";
            
            exit(1);
        }
        else {
            ## all good
            print STDERR "SUCCESS:  all commands completed succesfully. :)\n\n";
            
            exit(0);
        }
        
    }
}


exit(0);


####
sub get_next_fasta_entries {
    my ($fastaReader, $num_seqs) = @_;


    my $fasta_entries_txt = "";
    
    for (1..$num_seqs) {
        my $seq_obj = $fastaReader->next();
        unless ($seq_obj) {
            last;
        }

        my $entry_txt = $seq_obj->get_FASTA_format();
        $fasta_entries_txt .= $entry_txt;
    }

    return($fasta_entries_txt);
}
