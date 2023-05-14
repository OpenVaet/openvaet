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
use JSON;
use Text::CSV qw( csv );
use Encode;
use Encode::Unicode;
use Scalar::Util qw(looks_like_number);
use Math::Round qw(nearest);
use File::Path qw(make_path);
use FindBin;
use lib "$FindBin::Bin/../../../lib";
use time;

my %subjects = ();
my %adaes    = ();

load_adsl();
load_adae();

sub load_adsl {
	my $adslFile    = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv";
	die "you must convert the adsl file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv] first." unless -f $adslFile;
	open my $in, '<:utf8', $adslFile;
	my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels  = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	my %stats = ();
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
			open my $fh, "<", \$_;
			my $row = $dataCsv->getline ($fh);
			my @row = @$row;
			die scalar @row . " != $expectedValues" unless scalar @row == $expectedValues;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $dataLabels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}

			# Retrieve & apply the documented filters.
			# ADSL.PHASEN>1 and ADSL.AGEGR1N>1 and
			# ADSL.SAFFL="Y" and ADSL.MULENRFL^="Y" and
			# ADSL.HIVFL^="Y" and ADSL.TRT01A^=""
			my $subjid   = $values{'SUBJID'}   // die;
			my $phasen   = $values{'PHASEN'}   // die;
			my $agegr1n  = $values{'AGEGR1N'}  // die;
			my $saffl    = $values{'SAFFL'}    // die;
			my $mulenrfl = $values{'MULENRFL'} // die;
			my $hivfl    = $values{'HIVFL'}    // die;
			my $trt01a   = $values{'TRT01A'}   // die;

			next unless $phasen  > 1;  # ADSL.PHASEN>1
			next unless $agegr1n > 1;  # and ADSL.AGEGR1N>1
			next unless $saffl eq 'Y'; # and ADSL.SAFFL="Y"
			next if $mulenrfl  eq 'Y'; # and ADSL.MULENRFL^="Y"
			next if $hivfl     eq 'Y'; # and ADSL.HIVFL^="Y"
			next unless $trt01a;       # and ADSL.TRT01A^=""

			my $covblst  = $values{'COVBLST'}  // die;
			$stats{$covblst}++;
			$subjects{$subjid}->{'covblst'} = $covblst;
		}
	}
	close $in;
	$dRNum--;
	say "ADSL rows           : $dRNum";
	say "Subjects            : " . keys %subjects;
	say "COVBLST repartition :";
	p%stats;
}

sub load_adae {
	my $adslFile    = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv";
	die "you must convert the adsl file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0772469-0773670_125742_S1_M5_C4591001-A-D_adsl.csv] first." unless -f $adslFile;
	open my $in, '<:utf8', $adslFile;
	my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
	my %dataLabels  = ();
	my ($dRNum,
		$expectedValues) = (0, 0);
	my %stats = ();
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
			open my $fh, "<", \$_;
			my $row = $dataCsv->getline ($fh);
			my @row = @$row;
			die scalar @row . " != $expectedValues" unless scalar @row == $expectedValues;
			my $vN  = 0;
			my %values = ();
			for my $value (@row) {
				my $label = $dataLabels{$vN} // die;
				$values{$label} = $value;
				$vN++;
			}

			# Retrieve & apply the documented filters.
			# ADSL.PHASEN>1 and ADSL.AGEGR1N>1 and
			# ADSL.SAFFL="Y" and ADSL.MULENRFL^="Y" and
			# ADSL.HIVFL^="Y" and ADSL.TRT01A^=""
			my $subjid   = $values{'SUBJID'}   // die;
			my $phasen   = $values{'PHASEN'}   // die;
			my $agegr1n  = $values{'AGEGR1N'}  // die;
			my $saffl    = $values{'SAFFL'}    // die;
			my $mulenrfl = $values{'MULENRFL'} // die;
			my $hivfl    = $values{'HIVFL'}    // die;
			my $trt01a   = $values{'TRT01A'}   // die;

			next unless $phasen  > 1;  # ADSL.PHASEN>1
			next unless $agegr1n > 1;  # and ADSL.AGEGR1N>1
			next unless $saffl eq 'Y'; # and ADSL.SAFFL="Y"
			next if $mulenrfl  eq 'Y'; # and ADSL.MULENRFL^="Y"
			next if $hivfl     eq 'Y'; # and ADSL.HIVFL^="Y"
			next unless $trt01a;       # and ADSL.TRT01A^=""

			my $covblst  = $values{'COVBLST'}  // die;
			$stats{$covblst}++;
			$subjects{$subjid}->{'covblst'} = $covblst;
		}
	}
	close $in;
	$dRNum--;
	say "ADSL rows           : $dRNum";
	say "Subjects            : " . keys %subjects;
	say "COVBLST repartition :";
	p%stats;
}