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

my %edKids = ();
load_ed_kids();
my %xptData = ();
load_xpt_data();
my %pdfData = ();
load_pdf_data();
my %randomization = ();
my $randomizationFile  = 'public/doc/pfizer_trials/merged_doses_data.json';
load_randomization();

sub load_randomization {
	open my $in, '<:utf8', $randomizationFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomization = %$json;
	say "[$randomizationFile] -> patients : " . keys %randomization;
}

sub load_ed_kids {
	open my $in, '<:utf8', 'ed_kids_ids.csv';
	while (<$in>) {
		chomp $_;
		$edKids{$_} = 1;
	}
	close $in;
}

sub load_xpt_data {
	my $xptDataFile = 'public/doc/pfizer_trials/pfizer_sas_data_patients.json';
	open my $in, '<:utf8', $xptDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%xptData = %$json;
}

sub load_pdf_data {
	my $pdfDataFile = 'public/doc/pfizer_trials/pfizer_pdf_data_patients.json';
	open my $in, '<:utf8', $pdfDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdfData = %$json;
}

my %stats = ();
for my $subjectId (sort{$a <=> $b} keys %edKids) {
	# p$xptData{'subjects'}->{$subjectId};
	# p$pdfData{'subjects'}->{$subjectId};
	# p$randomization{$subjectId};
	# unless (exists $xptData{'subjects'}->{$subjectId}) {
	# 	die "indeed";
	# }
	# unless (exists $pdfData{'subjects'}->{$subjectId}) {
	# 	die "indeed";
	# }
	unless (exists $randomization{$subjectId}) {
		$stats{'noRandomizationData'}++;
		die "indeed";
	} else {
		p$randomization{$subjectId};
		$stats{'randomizationData'}++;
	}
}

p%stats;
# p$json;