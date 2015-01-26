../BioIfx/hpc_FASTA_GridRunner.pl \
        --cmd_template "hmmscan --cpu 8 --domtblout __QUERY_FILE__.domtblout /seq/RNASEQ/DBs/PFAM/current/Pfam-A.hmm __QUERY_FILE__" \
        --query_fasta test.pep \
        -G ../hpc_conf/BroadInst_LSF.test.conf \
        -N 10 -O test_pfam_search
