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

############################# Options ##################################################################################
#
# Required:
#
#   --query_fasta|Q <string>       query multiFastaFile (full or relative path)
#
#   --cmd_template|T <string>      program command line template:   eg. "/path/to/prog [opts] __QUERY_FILE__ [other opts]"
#
#  --grid_conf|G <string>          grid config file (see hpc_conf/ for examples)
#
#   --seqs_per_bin|N <int>         number of sequences per partition.
# 
#   --out_dir|O <string>           output directory 
#
# Optional:
#
#   --prep_only|X                  partion data and create cmds list, but don't launch on the grid.
#
#   --parafly                      use parafly to re-exec previously failed grid commands
#
###################### Process Args and Options ########################################################################


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

&GetOptions('query_fasta|Q=s' => \$query_fasta_file,
            'cmd_template|T=s' => \$program_cmd_template,
            'seqs_per_bin|N=i' => \$bin_size,
            'out_dir|O=s' => \$out_dir,
            'prep_only|X' => \$prep_only_flag,
            'grid_conf|G=s' => \$grid_conf_file,
            

            'help|h' => \$help,

    );



if ($help) {
    die $usage;
}

unless ($query_fasta_file && $program_cmd_template && $bin_size && $out_dir && $grid_conf_file) {
    die $usage;
}

unless ($query_fasta_file =~ /^\//) {
    $query_fasta_file = cwd() . "/$query_fasta_file";
}


unless ($program_cmd_template =~ /__QUERY_FILE__/) {
    die "Error, program cmd template must include '__QUERY_FILE__' placeholder in the command";
}


## Create files to search

my $fastaReader = new Fasta_reader($query_fasta_file);

my @searchFileList;

my $count = 0;
my $current_bin = 1;

mkdir $out_dir or die "Error, cannot mkdir $out_dir";

my $bindir = "$out_dir/grp_" . sprintf ("%04d", $current_bin);
mkdir ($bindir) or die "Error, cannot mkdir $bindir";


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
print STDERR "There are $numFiles blast search jobs to run.\n";

my $curr_dir = cwd;

if  ($numFiles) {
    
    my @cmds;
    ## formulate blast commands:
    foreach my $searchFile (@searchFileList) {
        $searchFile = "$curr_dir/$searchFile";
        
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

    my $cache_file = "$cmd_file.hpc-cache_success";
    
    my $grid_runner = new HPC::GridRunner($grid_conf_file, $cache_file);
    my $ret = $grid_runner->run_on_grid(@cmds);
        
    if ($ret) {
        
        print STDERR "Error, not all commands could complete successfully...\n\n";
        
        exit(1);
    }
    else {
        ## all good
        print STDERR "SUCESS:  all commands completed succesfully. :)\n\n";
        
        exit(0);
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
