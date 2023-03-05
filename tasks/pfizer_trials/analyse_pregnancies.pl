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
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);

my $pregnanciesFile = 'dailyclout_paper/pregnancies.csv';
my $pdfDataFile     = 'public/doc/pfizer_trials/pfizer_pdf_data_patients.json';
my $xptDataFile     = 'public/doc/pfizer_trials/pfizer_sas_data_patients.json';

my %xptData     = ();
my %pdfData     = ();

load_xpt_data();
load_pdf_data();
my %xptFiles    = ();
my %pregnancies = ();
load_pregnancies_data();

for my $xptFile (sort keys %xptFiles) {
	
}
p%xptFiles;
p%pregnancies;

sub load_xpt_data {
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
	open my $in, '<:utf8', $pdfDataFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdfData = %$json;
}

sub load_pregnancies_data {
	open my $in, '<:utf8', $pregnanciesFile;
	while (<$in>) {
		chomp $_;
		my @elems = split ';', $_;
		my $subjectId = $elems[scalar @elems - 1];
		die unless $subjectId;
		$pregnancies{$subjectId} = 1;
		# die unless exists $xptData{'subjects'}->{$subjectId}->{'files'};
		# die unless exists $pdfData{'subjects'}->{$subjectId}->{'files'};
		my $totalXptFiles = keys %{$xptData{'subjects'}->{$subjectId}->{'files'}};
		my $totalPdfFiles = keys %{$pdfData{'subjects'}->{$subjectId}->{'files'}};
		unless ($totalXptFiles && $totalPdfFiles) {
			say "subjectId     : [$subjectId]";
			say "totalXptFiles : [$totalXptFiles]";
			say "totalPdfFiles : [$totalPdfFiles]";
			p$xptData{'subjects'}->{$subjectId}->{'files'};
			p$pdfData{'subjects'}->{$subjectId}->{'files'};
			next;
		}
		for my $xptFile (sort keys %{$xptData{'subjects'}->{$subjectId}->{'files'}}) {
			$xptFiles{$xptFile} = 1;
		}
		# die;
	}
	close $in;
}

