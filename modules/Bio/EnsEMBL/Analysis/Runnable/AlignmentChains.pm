#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::Runnable::AlignmentChains

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::EnsEMBL::Analysis::Runnable::AlignmentChains;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::EnsEMBL::Utils::Argument qw( rearrange );

use Bio::EnsEMBL::Analysis::Runnable;
use Bio::EnsEMBL::DnaDnaAlignFeature;


@ISA = qw(Bio::EnsEMBL::Analysis::Runnable);

sub new {
  my ($class,@args) = @_;

  my $self = $class->SUPER::new(@args);
  
  my ($features, 
      $query_slice,
      $target_slices,
      $fa_to_nib,
      $lav_to_axt,
      $axt_chain,

      ) = $self->_rearrange([qw(FEATURES
                                QUERY_SLICE
                                TARGET_SLICES
                                FATONIB
                                LAVTOAXT
                                AXTCHAIN
                                )],
                                    @args);


  throw("You must supply a reference to an array of features with -features\n") 
      if not defined $features;
  throw("You must supply a query sequence\n") 
      if not defined $query_slice;
  throw("You must supply a hash ref of target sequences with -target_slices")
      if not defined $target_slices;

  $self->faToNib($fa_to_nib) if defined $fa_to_nib;
  $self->lavToAxt($lav_to_axt) if defined $lav_to_axt;
  $self->axtChain($axt_chain) if defined $axt_chain;

  $self->query_slice($query_slice);
  $self->target_slices($target_slices);
  $self->features($features);
  
  return $self;
}





=head2 run

  Title   : run
  Usage   : $self->run()
  Function: 
  Returns : none
  Args    : 

=cut

sub run {
  my ($self) = @_;

  my $query_name = $self->query_slice->seq_region_name;

  my $work_dir = $self->workdir . "/$query_name.$$.AxtChain";
  my $lav_file = "$work_dir/$query_name.lav";
  my $axt_file = "$work_dir/$query_name.axt";
  my $chain_file = "$work_dir/$query_name.chain";
  my $query_nib_dir = "$work_dir/query_nib";
  my $target_nib_dir = "$work_dir/target_nib";
  my @nib_files;

  mkdir $work_dir;
  mkdir $query_nib_dir;
  mkdir $target_nib_dir;

  my $fh;

  #################################
  # write the query in nib format 
  # for use by lavToAxt;
  #################################
  my $seqio = Bio::SeqIO->new(-format => 'fasta',
                              -file   => ">$query_nib_dir/$query_name.fa");
  $seqio->write_seq($self->query_slice);
  $seqio->close;

  system($self->faToNib, "$query_nib_dir/$query_name.fa", "$query_nib_dir/$query_name.nib") 
      and throw("Could not convert fasta file $query_nib_dir/$query_name.fa to nib");
  unlink "$query_nib_dir/$query_name.fa";
  push @nib_files, "$query_nib_dir/$query_name.nib";
  
  #################################
  # write the targets in nib format 
  # for use by lavToAxt;
  #################################  
  foreach my $nm (keys %{$self->target_slices}) {
    my $target = $self->target_slices->{$nm};
    my $target_name = $target->seq_region_name;
    
    $seqio =  Bio::SeqIO->new(-format => 'fasta',
                              -file   => ">$target_nib_dir/$target_name.fa");
    $seqio->write_seq($target);
    $seqio->close;
   
    system($self->faToNib, "$target_nib_dir/$target_name.fa", "$target_nib_dir/$target_name.nib") 
        and throw("Could not convert fasta file $target_nib_dir/$target_name.fa to nib");
    unlink "$target_nib_dir/$target_name.fa";
    push @nib_files, "$target_nib_dir/$target_name.nib";
  }
  
  ##############################
  # write features in lav format
  ############################## 
  open $fh, ">$lav_file" or 
      throw("could not open lav file '$lav_file' for writing\n");
  $self->write_lav($fh);
  close($fh);

  ##############################
  # convert the lav file to axt
  ##############################
  system($self->lavToAxt, $lav_file, $query_nib_dir, $target_nib_dir, $axt_file)
      and throw("Could not convert $lav_file to Axt format");

  ##################################
  # convert the lav file to axtChain
  ##################################
  system($self->axtChain, $axt_file, $query_nib_dir, $target_nib_dir, $chain_file)
        and throw("Something went wrong with axtChain\n");

  ##################################
  # read the chain file
  ##################################
  open $fh, $chain_file or throw("Could not open chainfile '$chain_file' for reading\n");
  my $chains = $self->parse_Chain_file($fh);

  $self->output($chains);  
  
  unlink $lav_file, $axt_file, $chain_file, @nib_files;
  rmdir $query_nib_dir;
  rmdir $target_nib_dir;
  rmdir $work_dir;

  return 1;
}


#####################################################

sub write_lav {  
  my ($self, $fh) = @_;

  my (%features);  
  foreach my $feat (sort {$a->start <=> $b->start} @{$self->features}) {
    push @{$features{$feat->hseqname}{$feat->strand}{$feat->hstrand}}, $feat;
  }
  
  my $query_length = $self->query_slice->length;
  my $query_name   = $self->query_slice->seq_region_name;
  
  foreach my $target (sort keys %features) {

    print $fh "#:lav\n";
    print $fh "d {\n   \"generated by Runnable/AxtFilter.pm\"\n}\n";

    foreach my $qstrand (keys %{$features{$target}}) {
      foreach my $tstrand (keys %{$features{$target}{$qstrand}}) {
        
        my $query_strand = ($qstrand == 1) ? 0 : 1;
        my $target_strand = ($tstrand == 1) ? 0 : 1;
        
        my $target_length = $self->target_slices->{$target}->length;

        print $fh "#:lav\n";
        print $fh "s {\n";
        print $fh "   \"$query_name\" 1 $query_length $query_strand 1\n";
        print $fh "   \"$target\" 1 $target_length $target_strand 1\n";
        print $fh "}\n";
        
        print $fh "h {\n";
        print $fh "   \">$query_name";
        if ($query_strand) {
          print $fh " (reverse complement)";
        }
        print $fh "\"\n   \">$target";
        if ($target_strand) {
          print $fh " (reverse complement)";
        }
        print $fh "\"\n}\n";
	
        foreach my $reg (@{$features{$target}{$qstrand}{$tstrand}}) {
          my $qstart = $query_strand ?  $query_length - $reg->end + 1 : $reg->start; 
          my $qend = $query_strand ?  $query_length - $reg->start + 1 : $reg->end; 
          my $tstart = $target_strand ? $target_length - $reg->hend + 1 : $reg->hstart; 
          my $tend = $target_strand ? $target_length - $reg->hstart + 1 : $reg->hend; 
          
          my $score = defined($reg->score) ? $reg->score : 100;
          my $percent_id = defined($reg->percent_id) ? $reg->percent_id : 100;

          printf $fh "a {\n   s %d\n", $score;
          print $fh "   b $qstart $tstart\n"; 
          print $fh "   e $qend $tend\n";
          
          foreach my $seg ($reg->ungapped_features) {
            my $qstartl = $query_strand ?  $query_length - $seg->end + 1 : $seg->start; 
            my $qendl = $query_strand ?  $query_length - $seg->start + 1 : $seg->end; 
            
            my $tstartl = $target_strand ? $target_length - $seg->hend + 1 : $seg->hstart; 
            my $tendl = $target_strand ? $target_length - $seg->hstart + 1 : $seg->hend; 
            
            printf $fh "   l $qstartl $tstartl $qendl $tendl %d\n", $percent_id;
            
          }
          print $fh "}\n";
        }
        
        print $fh "x {\n   n 0\n}\n"; 
      }
    }
    print $fh "m {\n   n 0\n}\n#:eof\n";
  }
}

##############################################################

sub parse_Chain_file {
  my ($self, $fh) = @_;

  my @chains;

  while(<$fh>) {
    
    /^chain\s+(\S.+)$/ and do {
      my @data = split /\s+/, $1;

      my $chain = {
        q_id     => $data[1],
        q_len    => $data[2],
        q_strand => $data[3] eq "-" ? -1 : 1,
        t_id     => $data[6],
        t_len    => $data[7],
        t_strand => $data[8] eq "-" ? -1 : 1,
        score    => $data[0],
        blocks   => [],
      };

      my ($current_q_start, $current_t_start) = ($data[4] + 1, $data[9] + 1);
      my @blocks = ([]);
      
      while(<$fh>) {
        if (/^(\d+)(\s+\d+\s+\d+)?$/) {
          my ($ungapped, $rest) = ($1, $2);

          my ($current_q_end, $current_t_end) = 
              ($current_q_start + $ungapped - 1, $current_t_start + $ungapped - 1);

          push @{$blocks[-1]}, { q_start => $current_q_start,
                                 q_end   => $current_q_end,
                                 t_start => $current_t_start,
                                 t_end   => $current_t_end,
                               };
          
          if ($rest and $rest =~ /\s+(\d+)\s+(\d+)/) {
            my ($gap_q, $gap_t) = ($1, $2);
            
            $current_q_start = $current_q_end + $gap_q + 1;
            $current_t_start = $current_t_end + $gap_t + 1; 
            
            if ($gap_q != 0 and $gap_t !=0) {
              # simultaneous gap; start a new block
              push @blocks, [];
            }
          } else {
            # we just had a line on its own;
            last;
          }
        } 
        else {
          throw("Not expecting line '$_' in chain file");
        }
      }

      # can now form the cigar string and flip the reverse strand co-ordinates
      foreach my $block (@blocks) {
        my @ug_feats;

        foreach my $ug_feat (@$block) {
          if ($chain->{q_strand} < 0) {
            my ($rev_q_start, $rev_q_end) = ($ug_feat->{q_start}, $ug_feat->{q_end});
            $ug_feat->{q_start} = $chain->{q_len} - $rev_q_end + 1;
            $ug_feat->{q_end}     = $chain->{q_len} - $rev_q_start + 1;
          }
          if ($chain->{t_strand} < 0) {
            my ($rev_t_start, $rev_t_end) = ($ug_feat->{t_start}, $ug_feat->{t_end});
            $ug_feat->{t_start} = $chain->{t_len} - $rev_t_end + 1;
            $ug_feat->{t_end}   = $chain->{t_len} - $rev_t_start + 1;
          }

          #create featurepair
          my $fp = new Bio::EnsEMBL::FeaturePair->new();
          $fp->seqname($chain->{q_id});
          $fp->start($ug_feat->{q_start});
          $fp->end($ug_feat->{q_end});
          $fp->strand($chain->{q_strand});
          $fp->hseqname($chain->{t_id});
          $fp->hstart($ug_feat->{t_start});
          $fp->hend($ug_feat->{t_end});
          $fp->hstrand($chain->{t_strand});
          $fp->score($chain->{score});
        
          push @ug_feats, $fp;
        }
       
        push @{$chain->{blocks}}, new Bio::EnsEMBL::DnaDnaAlignFeature(-features => \@ug_feats);
      }

      push @chains, $chain->{blocks};
    }
  }

  return \@chains;
}



#####################
# instance vars
#####################

sub query_slice {
  my ($self, $slice) = @_;
  
  if (defined $slice) {
    $self->{_query_slice} = $slice;
  }
  return $self->{_query_slice};
}

sub target_slices {
  my ($self, $hash_ref) = @_;
  
  if (defined $hash_ref) {
    $self->{_target_slices_hashref} = $hash_ref;
  }
  return $self->{_target_slices_hashref};
}

sub features {
  my ($self, $features) = @_;

  if (defined $features) {
    $self->{_features} = $features;
  }

  return $self->{_features};
}


##############
#### programs
##############

sub faToNib {
  my ($self,$arg) = @_;
  
  if (defined($arg)) {
    $self->{'_faToNib'} = $arg;
  }

  return $self->{'_faToNib'};
}


sub lavToAxt {
  my ($self,$arg) = @_;
  
  if (defined($arg)) {
    $self->{'_lavToAxt'} = $arg;
  }

  return $self->{'_lavToAxt'};
}


sub axtChain {
  my ($self,$arg) = @_;
  
  if (defined($arg)) {
    $self->{'_axtChain'} = $arg;
  }
  
  return $self->{'_axtChain'};
}



1;
