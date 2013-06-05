#!/usr/bin/perl

use warnings;
use strict;
use Getopt::Long;
use Bio::Seq;
use Bio::SeqIO;

my $indel = "";
my $indel_type = "";
my $indel_ref = "";
my $indel_ref_start = 0;
my $indel_query = "";
my $indel_query_start = 0;
my $fasta_file = "";
my $o_type = "";
my $o_snpEffect = 0;;
my $ref_fasta_io;
my $ref_fasta_seq;

GetOptions('fasta=s' => \$fasta_file,
           'type=s' => \$o_type,
           'snpEffect' => \$o_snpEffect) or die("couldn't deal with options");
die("--type must be SNP or INDEL") if $o_type and $o_type ne "INDEL" and $o_type ne "SNP";

if ($o_type ne "SNP") {
    my $firstline = <>;
    if ($fasta_file eq "") {
        ($fasta_file, undef) = split /\s+/, $firstline;
    }
    die("must specify Fasta reference with -f/--fasta <file>") if $fasta_file eq "";
    $ref_fasta_io = Bio::SeqIO->new(-file => "<$fasta_file", -format => "fasta");
}

sub find_ref_fasta_seq($) {
    return if $o_type eq "SNP";
    # read fasta sequences until we load the requested one
    my $seq_name_to_find = shift;
    # if we return below, then we are already at the sequence of interest
    if (defined($ref_fasta_seq) and $ref_fasta_seq->id eq $seq_name_to_find) {
        #print STDERR "find_ref_fasta_seq: we are already at the reference sequence $seq_name_to_find\n";
        return;
    }
    return if defined($ref_fasta_seq) and $ref_fasta_seq->id eq $seq_name_to_find;
    while (my $s = $ref_fasta_io->next_seq()) {
        if ($s->id eq $seq_name_to_find) {
            $ref_fasta_seq = $s;
            #print STDERR "find_ref_fasta_seq: found new reference sequence $seq_name_to_find\n";
            return;
        }
    }
    die("couldn't find reference $seq_name_to_find");
}
sub complete_indel() {
    # we don't know the ref base at the start, so just try to fake it with ""
    # 
    if ($o_type ne "SNP") {
        my $alt = ""; # if we don't have a reference sequence this is all we know

        # fetch the ref base from the reference sequence
        find_ref_fasta_seq($indel_ref);
        my $ref_base = $ref_fasta_seq->subseq($indel_ref_start - 1, $indel_ref_start - 1);
        $indel = $ref_base . $indel;
        $alt = $ref_base;
        if ($indel_type eq "INSERTION") {
            #print STDOUT join("\t", $indel_ref, $indel_ref_start, $alt, $indel, $indel_type), "\n";
            print STDOUT join("\t", $indel_ref, $indel_ref_start, $alt, $indel, "INDEL"), "\n";
        } elsif ($indel_type eq "DELETION") {
            #print STDOUT join("\t", $indel_ref, $indel_ref_start, $indel, $alt, $indel_type), "\n";
            print STDOUT join("\t", $indel_ref, $indel_ref_start, $indel, $alt, "INDEL"), "\n";
        } else {
            die("complete_indel: oops");
        }
    }
    $indel = "";
    $indel_type = "";
    $indel_ref = "";
    $indel_ref_start = 0;
    $indel_query = "";
    $indel_query_start = 0;
}
sub complete_snp($$$$) {
    if ($o_type ne "INDEL") {
        my ($ref, $pos, $orig, $alt) = @_;
        print STDOUT join("\t", $ref, $pos, $orig, $alt, "SNP"), "\n";
    }
}

while (<>) {
    last if (/^NUCMER/);  # skip all lines til NUCMER
}
if ($o_snpEffect) {
    # print snpEffect header, first 4 (strictly middle 3) are required
    print STDOUT join("\t", "Reference", "Position", "ReferenceAllele", "SNPAllele", "Type"), "\n";
} else {
    # print VCF header
}
while (<>) {
    next if /(^NUCMER|^\s*$|^\[)/;  # skip headers and blank lines
    my @line = split;
    if ($indel and (($line[1] eq "." and $line[0] != $indel_ref_start) 
                    or ($line[2] eq "." and $line[3] != $indel_query_start))) {
        # we have another indel but a new one
        complete_indel();
    }
    if( $line[1] eq "." || $line[2] eq ".") {
        if ($indel eq "") {
            # a new indel, track it
            $indel_ref = $line[10];
            $indel_ref_start = $line[0];
            $indel_query = $line[11];
            $indel_query_start = $line[3];
            $indel_type = $line[1] eq "." ? "INSERTION" : "DELETION";
        }
        if ($line[1] eq ".") { # insertion in query
            $indel .= $line[2];
        } elsif ($line[2] eq ".") { # deletion in query
            $indel .= $line[1];
        } else {
            die("oops");
        }
    } else {
        # a snp
        complete_indel() if $indel;
        complete_snp($line[10], $line[0], $line[1], $line[2]);
    }
}
complete_indel() if $indel;

