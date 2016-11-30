# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use Bio::EnsEMBL::Registry;


## Load the registry automatically
my $reg = "Bio::EnsEMBL::Registry";
$reg->load_registry_from_url('mysql://anonymous@ensembldb.ensembl.org');


# Get the Compara GenomeDB Adaptor
my $genome_db_adaptor = Bio::EnsEMBL::Registry->get_adaptor( "Multi", "compara", "GenomeDB");

# Get the GenomeDB for the chimp (pan_troglodytes) genome
my $chimp_genome_db = $genome_db_adaptor->fetch_by_registry_name("chimp");

# Get the Compara DnaFrag Adaptor
my $dnafrag_adaptor = Bio::EnsEMBL::Registry->get_adaptor( "Multi", "compara", "DnaFrag");

# Get all the DnaFrags for chimp
my $dnafrags = $dnafrag_adaptor->fetch_all_by_GenomeDB_region($chimp_genome_db, 'chromosome');

print "For ", $chimp_genome_db->name(), " :\n";
foreach my $dnafrag(@{ $dnafrags }){
	print "Chromsome ", $dnafrag->name(), " contains ", $dnafrag->length(), " bp.\n";
}
