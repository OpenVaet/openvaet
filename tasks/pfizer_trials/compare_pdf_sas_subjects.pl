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

my $sasSubjectsFile = 'public/doc/pfizer_trials/pfizer_sas_data_patients.json';
my $pdfSubjectsFile = 'public/doc/pfizer_trials/pfizer_pdf_data_patients.json';

my %sasSubjects = ();
my %pdfSubjects = ();

load_sas_subjects();
load_pdf_subjects();

my %stats = ();
for my $subjectId (sort{$a <=> $b} keys %{$sasSubjects{'subjects'}}) {
	unless (exists $pdfSubjects{'subjects'}->{$subjectId}) {
		say "appears in [SAS] but not in [PDF] : $subjectId";
		my $hasDsFile = 0;
		for my $file (sort keys %{$sasSubjects{'subjects'}->{$subjectId}->{'files'}}) {
			if ($file eq 'raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0171524-to-0174606_125742_S1_M5_c4591001-S-D-suppds.csv') {
				$hasDsFile = 1;
			}
		}
		# p$sasSubjects{'subjects'}->{$subjectId};
		die unless $hasDsFile == 1;
		$stats{'inSasNotInPdf'}++;
	}
}
for my $subjectId (sort{$a <=> $b} keys %{$pdfSubjects{'subjects'}}) {
	unless (exists $sasSubjects{'subjects'}->{$subjectId}) {
		say "appears in [PDF] but not in [SAS] : $subjectId";
		$stats{'inPdfNotInSas'}++;
		die;
	}
}
p%stats;

sub load_sas_subjects {
	open my $in, '<:utf8', $sasSubjectsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%sasSubjects = %$json;
}

sub load_pdf_subjects {
	open my $in, '<:utf8', $pdfSubjectsFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdfSubjects = %$json;
}