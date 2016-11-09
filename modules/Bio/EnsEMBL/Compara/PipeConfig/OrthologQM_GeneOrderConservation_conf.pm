=pod
=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2017] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <http://www.ensembl.org/Help/Contact>.

=head1 NAME
	
	Bio::EnsEMBL::Compara::PipeConfig::OrthologQM_GeneOrderConservation_conf;

=head1 DESCRIPTION
    if a default threshold is not given the pipeline will use the genetic distance between the pair species to choose between a threshold of 50 and 75 percent.
	http://www.ebi.ac.uk/seqdb/confluence/display/EnsCom/Quality+metrics+for+the+orthologs


    Example run
        init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::OrthologQM_GeneOrderConservation_conf -goc_mlss_id <20620> -goc_threshold (optional) -pipeline_name <GConserve_trial> -host <host_server> -reuse_goc <1/0> -prev_rel_db <> -compara_db <>

=cut


package Bio::EnsEMBL::Compara::PipeConfig::OrthologQM_GeneOrderConservation_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;  
use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');
use Bio::EnsEMBL::Compara::PipeConfig::Parts::GOC;

sub hive_meta_table {
    my ($self) = @_;
    return {
        %{$self->SUPER::hive_meta_table},       # here we inherit anything from the base class

        'hive_use_param_stack'  => 1,           # switch on the new param_stack mechanism
    };
}


sub default_options {
    my $self = shift;
    return {
            %{ $self->SUPER::default_options() },

        'goc_mlss_id'     => undef, #'100021',
        'compara_db' => undef, #'mysql://ensadmin:'.$ENV{ENSADMIN_PSW}.'@compara2/wa2_protein_trees_snapshot_84'
#        'compara_db' => 'mysql://ensro@compara4/OrthologQM_test_db'
        'goc_threshold' => undef,
        'prev_rel_db'  => undef,
        'reuse_goc'     => undef,
        'goc_capacity'   => 200,
    };
}

sub pipeline_wide_parameters {
    my ($self) = @_;
    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class
        'goc_mlss_id' => $self->o('goc_mlss_id'),
        'compara_db' => $self->o('compara_db'),
        'goc_threshold'  => $self->o('goc_threshold'),
        'prev_rel_db'  => $self->o('prev_rel_db'),
        'reuse_goc'     => $self->o('reuse_goc'),
        'goc_capacity'   => $self->o('goc_capacity'),
    };
}

sub resource_classes {
    my ($self) = @_;
    return {
        %{$self->SUPER::resource_classes},  # inherit 'default' from the parent class
        '1Gb_job'      => {'LSF' => '-C0 -M1000 -q production-rh7 -R"select[mem>1000]  rusage[mem=1000]"' },
        '2Gb_job'      => {'LSF' => '-C0 -M2000 -q production-rh7 -R"select[mem>2000]  rusage[mem=2000]"' },
        '16Gb_job'      => {'LSF' => '-C0 -M16000 -q production-rh7 -R"select[mem>16000]  rusage[mem=16000]"' },
    };
}


sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'goc_entry_point',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::Dummy',
            -flow_into  => {
                '1->A' => WHEN( '#reuse_goc#' => 'copy_prev_goc_score_table',
                    ),
                'A->1' => {
                    'get_orthologs' => { 'goc_mlss_id' => $self->o('goc_mlss_id') }, 
		},
            },
        },

        {   -logic_name => 'copy_prev_goc_score_table',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer',
            -parameters => {
                'src_db_conn'   => '#prev_rel_db#',
                'mode'          => 'overwrite',
                'filter_cmd'        => 'sed "s/CREATE TABLE #table#/CREATE TABLE prev_rel_goc_metrics/"',
                'table'         => 'ortholog_goc_metric',
            },
            -flow_into  =>  ['copy_prev_gene_member_table'],
        },
        
        {   -logic_name => 'copy_prev_gene_member_table',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer',
            -parameters => {
                'src_db_conn'   => '#prev_rel_db#',
                'mode'          => 'overwrite',
                'filter_cmd'        => 'sed "s/CREATE TABLE #table#/CREATE TABLE prev_rel_gene_member_table/"',
                'table'         => 'gene_member',
            },
        },

        @{ Bio::EnsEMBL::Compara::PipeConfig::Parts::GOC::pipeline_analyses_goc($self)  },
	];
}

1;
