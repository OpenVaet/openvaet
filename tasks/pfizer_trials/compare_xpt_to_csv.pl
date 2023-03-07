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

my $synthesisFile = 'public/doc/pfizer_trials/xpt_to_csv_conversion.csv';

my %xpts = ();
for my $file (glob "public/pfizer_documents/native_files/pd-production-*/*.xpt") {
	my ($fileName) = $file =~ /public\/pfizer_documents\/native_files\/pd-production-.*\/(.*)\.xpt/;
	$fileName =~ s/ to /-to-/g;
	$fileName =~ s/ //g;
	$fileName =~ s/--/-/g;
	$fileName =~ s/\.xpt$//;
	# say "file     : $file";
	# say "fileName : $fileName";
	$xpts{$fileName}->{'sourceXptFile'} = $file;
}
# p%xpts;

my %csvs = ();
for my $file (glob "raw_data/pfizer_trials/xpt_files_to_csv/*.csv") {
	my ($fileName) = $file =~ /raw_data\/pfizer_trials\/xpt_files_to_csv\/(.*)\.csv/;
	# say "file     : $file";
	# say "fileName : $fileName";
	die "fileName : $fileName" unless exists $xpts{$fileName};
	$csvs{$fileName}->{'csvFile'} = $file;
}

open my $out, '>:utf8', $synthesisFile;
for my $fileName (sort keys %xpts) {
	unless (exists $csvs{$fileName}->{'csvFile'}) {
		my $sourceXptFile = $xpts{$fileName}->{'sourceXptFile'} // die;
		say "Missing :";
		say "fileName      : $fileName";
		say "sourceXptFile : $sourceXptFile";
	} else {
		my $sourceXptFile = $xpts{$fileName}->{'sourceXptFile'} // die;
		my $csvFile = $csvs{$fileName}->{'csvFile'} // die;
		say "Exists :";
		say "fileName      : $fileName";
		say "sourceXptFile : $sourceXptFile";
		say "--->  csvFile : $csvFile";
		say $out "$csvFile;$sourceXptFile;";
	}
}
close $out;