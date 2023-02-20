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
use lib "$FindBin::Bin/../../lib";
use time;

my $dt19600101 = '1960-01-01 12:00:00';
my $tp19600101 = time::datetime_to_timestamp($dt19600101);
my $altShotsFile = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0282130-to-0282328_125742_S1_M5_c4591001-S-D-cm.csv";
my $randomizationFile  = 'public/doc/pfizer_trials/merged_doses_data.json';
die "you must convert the altShots file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0282130-to-0282328_125742_S1_M5_c4591001-S-D-cm.csv] first." unless -f $altShotsFile;
my %randomizationData = ();
randomization_data();

my %stats = ();

open my $in, '<:utf8', $altShotsFile;
my $dataCsv    = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels = ();
my ($dRNum,
	$expectedValues) = (0, 0);
my %subjects   = ();
open my $outAltShots, '>:utf8', 'concomitant_medicines.csv';
say $outAltShots "subjectId;uSubjectId;cmDecod;cmDose;cMSTDTC;";
while (<$in>) {
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
		# p%values;
		# die;

		# Fetching the data we currently focus on.
		my $cmCat        = $values{'CMCAT'}      // die;
		my $uSubjectId   = $values{'USUBJID'}    // die;
		my ($subjectId)  = $uSubjectId =~ /........ .... (........)/;
		my $cmDecod      = lc $values{'CMDECOD'} // die;
		my $cmDose       = $values{'CMDOSE'}     // die;
		say "cmDecod : $cmDecod";
		my $cmDosu       = $values{'CMDOSU'}     // die;
		my $cMSTDTC      = $values{'CMSTDTC'}    // die;
		$subjects{$subjectId}->{'totalDoses'}++;
		my $altDoseNum   = $subjects{$subjectId}->{'totalDoses'} // die;
		my $hasInfluenza = 0;
		if ($cmDecod =~ /influenza/) {
			$hasInfluenza = 1;
		}
		if ($hasInfluenza == 1) {
			$subjects{$subjectId}->{'hasInfluenza'} = $hasInfluenza;
			$subjects{$subjectId}->{'lastDate'} = $cMSTDTC if $cMSTDTC;
		} else {
			unless ($subjects{$subjectId}->{'hasInfluenza'}) {
				$subjects{$subjectId}->{'hasInfluenza'} = $hasInfluenza;
				$subjects{$subjectId}->{'lastDate'} = $cMSTDTC if $cMSTDTC;
			}
		}
		$cmDecod =~ s/;/ - /g;
		$cmDose  =~ s/;/ - /g;
		say $outAltShots "$subjectId;$uSubjectId;$cmDecod;$cmDose;$cMSTDTC;";
		$subjects{$subjectId}->{'otherShots'}->{$altDoseNum}->{'cmCat'}   = $cmCat;
		$subjects{$subjectId}->{'otherShots'}->{$altDoseNum}->{'cmDecod'} = $cmDecod;
		$subjects{$subjectId}->{'otherShots'}->{$altDoseNum}->{'cMSTDTC'} = $cMSTDTC;
		$subjects{$subjectId}->{'otherShots'}->{$altDoseNum}->{'cmDose'}  = $cmDose;
		$subjects{$subjectId}->{'otherShots'}->{$altDoseNum}->{'cmDosu'}  = $cmDosu;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		$subjects{$subjectId}->{'uSubjectId'} = $uSubjectId;
		$subjects{$subjectId}->{'totalRows'}++;
		unless (exists $randomizationData{$subjectId}) {
			$stats{'missingRandomizationData'}++;
		} else {
			if ($hasInfluenza) {
				my $randomizationGroup = $randomizationData{$subjectId}->{'randomizationGroup'} // die;
				$stats{'influenzaJabbed'}->{$randomizationGroup}++;
				# p$randomizationData{$subjectId};
				# di
			}
		}
		# p%subjects;
		# die;
	}
}
close $outAltShots;
close $in;
say "dRNum           : $dRNum";
say "patients        : " . keys %subjects;

# my $outputFolder   = "public/doc/pfizer_trials";
# make_path($outputFolder) unless (-d $outputFolder);

# # Prints patients JSON.
# open my $out, '>:utf8', "$outputFolder/pfizer_alt_shots_patients.json";
# print $out encode_json\%subjects;
# close $out;

# for my $subjectId (sort{$a <=> $b} keys %subjects) {
# 	for my $doseNum (sort{$a <=> $b} keys %{$subjects{$subjectId}->{'otherShots'}}) {
# 		my $cmCat   = $subjects{$subjectId}->{'otherShots'}->{$doseNum}->{'cmCat'}   // die;
# 		my $cmDecod = $subjects{$subjectId}->{'otherShots'}->{$doseNum}->{'cmDecod'} // die;
# 		$stats{$cmDecod}->{'totalDoses'}++;
# 		say "cmDecod : [$cmDecod]";
# 	}
# }

# open my $out2, '>:utf8', 'other_products.csv';
# say $out2 "Product;Total Subjects & Doses;";
# for my $cmDecod (sort keys %stats) {
# 	my $doses = $stats{$cmDecod}->{'totalDoses'} // die;
# 	$cmDecod =~ s/;/ - /g;
# 	say $out2 "$cmDecod;$doses;";
# }
# close $out2;
p%stats;

# p%subjects;

sub randomization_data {
	open my $in, '<:utf8', $randomizationFile;
	my $json;
	while (<$in>) {
		$json .= $_;
	}
	close $in;
	$json = decode_json($json);
	%randomizationData = %$json;
	# p%randomizationData;
	# die;
}