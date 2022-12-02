#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
no autovivification;
use utf8;
use JSON;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

my $filesDetails = 'public/doc/pfizer_trials/pfizer_pdf_data_patients.json';

my %stats      = ();
my %filesData  = ();
my %subjects   = ();

load_file_data();

for my $subjectId (sort{$a <=> $b} keys %{$filesData{'subjects'}}) {
	my ($hasBoth, $hasInterim, $hasMonth6) = (0, 0, 0);
	for my $file (sort keys %{$filesData{'subjects'}->{$subjectId}->{'files'}}) {
		next unless $file eq 'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-randomization-sensitive.pdf' ||
					$file eq 'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_c4591001-interim-mth6-randomization-sensitive.pdf';
		$hasInterim = 1 if $file eq 'pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-randomization-sensitive.pdf';
		$hasMonth6  = 1 if $file eq 'pfizer_documents/native_files/pd-production-050222/125742_S1_M5_5351_c4591001-interim-mth6-randomization-sensitive.pdf';
	}
	$hasBoth = 1 if $hasInterim == 1 && $hasMonth6 == 1;
	$subjects{$subjectId}++;
	$stats{'hasBoth'}->{$hasBoth}++;
	$stats{'hasInterim'}->{$hasInterim}++;
	$stats{'hasMonth6'}->{$hasMonth6}++;
}

open my $out, '>:utf8', 'public/doc/pfizer_trials/randomized_patients.json';
print $out encode_json\%subjects;
close $out;
# p%stats;

say "Subjects randomized : " . keys %subjects;

sub load_file_data {
	open my $in, '<:utf8', $filesDetails;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%filesData = %$json;
}