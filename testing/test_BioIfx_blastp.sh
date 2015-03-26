../BioIfx/hpc_FASTA_GridRunner.pl \
        --cmd_template "blastp -query __QUERY_FILE__ -db /seq/RNASEQ/DBs/SWISSPROT/current/uniprot_sprot.pep  -max_target_seqs 1 -outfmt 6 -evalue 1e-5" \
        --query_fasta `pwd`/test.pep \
        -G ../hpc_conf/BroadInst_LSF.test.conf \
        -N 10 -O test_blastp_search
