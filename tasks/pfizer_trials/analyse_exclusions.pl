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
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;

my $pdfFile1         = 'excluded subjects 6 month.csv';
my $pdfFile2         = 'public/doc/pfizer_trials/pfizer_trial_deviations_1.json';
my $pdfFile3         = 'public/doc/pfizer_trials/pfizer_trial_deviations_2.json';

my %pdf_exclusions_1 = ();
my %pdf_exclusions_2 = ();
my %pdf_exclusions_3 = ();

load_pdf_exclusions_1();
load_pdf_exclusions_2();
load_pdf_exclusions_3();

sub load_pdf_exclusions_1 {
	open my $in, '<:utf8', $pdfFile1;
	my $lNum = 0;
	while (<$in>) {
		$lNum++;
		next if $lNum == 1;
		my (undef, $uSubjectId) = split ';', $_;
		my ($subjectId)       = $uSubjectId =~ /^C4591001 .... (.*)$/;
		die unless $subjectId && $subjectId =~ /^........$/;
		die unless $uSubjectId =~ /$subjectId$/;
		$pdf_exclusions_1{$subjectId} = 1;
	}
	close $in;
	say "[$pdfFile1] -> subjects : " . keys %pdf_exclusions_1;
}

sub load_pdf_exclusions_2 {
	open my $in, '<:utf8', $pdfFile2;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdf_exclusions_2 = %$json;
	say "[$pdfFile2] -> subjects : " . keys %pdf_exclusions_2;
}

sub load_pdf_exclusions_3 {
	open my $in, '<:utf8', $pdfFile3;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%pdf_exclusions_3 = %$json;
	say "[$pdfFile3] -> subjects : " . keys %pdf_exclusions_3;
}

my %stats    = ();
my %subjects = ();
for my $subjectId (sort keys %pdf_exclusions_1) {
	die if exists $subjects{$subjectId};
	# $subjects{$subjectId}->{'sources'}->{'pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-excluded-patients-sensitive.pdf'} = 1;
	# $stats{'subjectsExcludedInPdfs'}++;
	$subjects{$subjectId}->{'subjectId'} = $subjectId;
	# p$pdf_exclusions_1{$subjectId};
	# die;
}
for my $subjectId (sort keys %pdf_exclusions_2) {
	# $subjects{$subjectId}->{'sources'}->{'pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-excluded-patients-sensitive.pdf'} = 1;
	# $stats{'subjectsExcludedInPdfs'}++;
	$subjects{$subjectId}->{'subjectId'} = $subjectId;
	# p$pdf_exclusions_1{$subjectId};
	# die;
}
for my $subjectId (sort keys %pdf_exclusions_3) {
	# $subjects{$subjectId}->{'sources'}->{'pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-excluded-patients-sensitive.pdf'} = 1;
	# $stats{'subjectsExcludedInPdfs'}++;
	$subjects{$subjectId}->{'subjectId'} = $subjectId;
	# p$pdf_exclusions_1{$subjectId};
	# die;
}
p%stats;
say "[all files] -> subjects : " . keys %subjects;