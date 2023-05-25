#!/usr/bin/perl
use strict;
use warnings;
use v5.26;
use Data::Dumper;
use Data::Printer;
binmode STDOUT, ":utf8";
use utf8;
use open ':std', ':encoding(UTF-8)';
no autovivification;
use utf8;
use Text::CSV qw( csv );
use Encode;
use Encode::Unicode;

my $f1 = 'tasks/pfizer_trials/j_r/anysae.csv';
my $f2 = 'tasks/pfizer_trials/j_r/filtered_subjects_lin_reg.csv';

my %josh  = ();
my %current = ();
load_josh_bnt();
load_current_bnt();

for my $subjid (sort keys %josh) {
	unless (exists $current{$subjid}) {
		say "missing from current : [$subjid]";
	}
}
for my $subjid (sort keys %current) {
	unless (exists $josh{$subjid}) {
		say "missing from josh  : [$subjid]";
	}
}

sub load_josh_bnt {
	open my $in, '<:utf8', $f1;
	while (<$in>) {
		chomp $_;
		my ($subjid) = split ';', $_;
		next if $subjid eq 'subjid';
		$josh{$subjid} = 1;
	}
	close $in;
}

sub load_current_bnt {
	my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels  = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	open my $in, '<:utf8', $f2;
	while (<$in>) {
		chomp $_;
		$dRNum++;

		# Verifying line.
		my $line = $_;
		$line = decode("ascii", $line);
		for (/[^\n -~]/g) {
		    printf "Bad character: %02x\n", ord $_;
		    die;
		}

		# First row = line labels.
		if ($dRNum == 1) {
			my @labels = split ',', $line;
			my $lN = 0;
			for my $label (@labels) {
				$label =~ s/\"//g;
				$dataLabels{$lN} = $label;
				$lN++;
			}
			$expectedValues = keys %dataLabels;
		} else {

			# Verifying we have the expected number of values.
			my @row = split ",", $line;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $dataLabels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}
			# p%values;die;
			my $subjid    = $values{'subjid'}    // die;
			my $actarm    = $values{'actarm'}    // die;
			my $aeserRows = $values{'aeserRows'} // die;
			next if $aeserRows < 1;
			$current{$subjid} = 1;
		}

	}
	close $in;
}