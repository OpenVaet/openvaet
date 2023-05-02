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

my $dt19600101  = '1960-01-01 12:00:00';
my $tp19600101  = time::datetime_to_timestamp($dt19600101);
my $adaeFile = "raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv";
die "you must convert the adae file using readstats and place it in [raw_data/pfizer_trials/xpt_files_to_csv/FDA-CBER-2021-5683-0774873-0775804_125742_S1_M5_C4591001-A-D_adae.csv] first." unless -f $adaeFile;
open my $in, '<:utf8', $adaeFile;
my $dataCsv     = Text::CSV_XS->new ({ binary => 1 });
my %dataLabels  = ();
my ($dRNum,
	$expectedValues) = (0, 0);
my %subjects    = ();
my %noDates     = ();
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
		# open my $out, '>:utf8', 'sample_ae.json';
		# print $out encode_json\%values;
		# close $out;
		# p%values;
		# die;

		# Fetching the data we currently focus on.
		my $subjectId         = $values{'SUBJID'}   // die;
		my $uSubjectId        = $values{'USUBJID'}  // die;
		my $vPhase            = $values{'VPHASE'}   // die;
		my $aperiodDc         = $values{'APERIODC'} // die;
		my $relation          = $values{'AREL'}     // die;
		my $aehlgt            = $values{'AEHLGT'}   // die;
		my $aehlt             = $values{'AEHLT'}    // die;
		my $aeser             = $values{'AESER'}    // die;
		my $aeRelTxt          = $values{'AERELTXT'} // die;
		my $toxicityGrade     = $values{'ATOXGR'}   // die;
		$toxicityGrade        =~ s/GRADE //;
		my $aeStdDt           = $values{'AESTDTC'}  // die;
		my $aeEndDt           = $values{'AEENDTC'}  // die;
		$aeStdDt              =~ s/T/ /;
		my $aeTerm            = $values{'AETERM'}   // die;
		my ($aeCompdate) = split ' ', $aeStdDt;
		if ($aeCompdate) {
			$aeCompdate =~ s/\D//g;
			my ($aeY, $aeM, $aeD) = $aeCompdate =~ /(....)(..)(..)/;
			unless ($aeY && $aeM && $aeD) {
				$aeCompdate = undef;
			}
		}
		$subjects{$subjectId}->{'totalADAERows'}++;
		$subjects{$subjectId}->{'uSubjectIds'}->{$uSubjectId} = 1;
		$subjects{$subjectId}->{'uSubjectId'} = $uSubjectId;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aeCompdate'} = $aeCompdate;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'toxicityGrade'} = $toxicityGrade;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aeStdDt'} = $aeStdDt;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aehlgt'} = $aehlgt;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aeTerm'} = $aeTerm;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aehlt'} = $aehlt;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aeser'} = $aeser;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aeRelTxt'} = $aeRelTxt;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aeEndDt'} = $aeEndDt;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'aperiodDc'} = $aperiodDc;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'relation'} = $relation;
		$subjects{$subjectId}->{'adverseEffects'}->{$dRNum}->{'vPhase'} = $vPhase;
		# p$subjects{$subjectId};
		# die;
	}
}
close $in;
$dRNum--;
say "dRNum           : $dRNum";
say "patients        : " . keys %subjects;
say "no date         : " . keys %noDates;

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_adae_patients.json";
print $out encode_json\%subjects;
close $out;

# Prints missing subjects.
open my $out2, '>:utf8', "$outputFolder/adae_missing_dates_rows.csv";
# .CSV Header
for my $subjectId (sort keys %noDates) {
	for my $label (sort keys %{$noDates{$subjectId}}) {
		print $out2 "$label;";
	}
	last;
}
print $out2 "\n";
# .CSV Values
my %sitesTargeted      = ();
$sitesTargeted{'1133'} = 'ee8493';
$sitesTargeted{'1135'} = 'ee8493';
$sitesTargeted{'1146'} = 'ee8493';
$sitesTargeted{'1170'} = 'ee8493';
$sitesTargeted{'1001'} = 'ej0553';
$sitesTargeted{'1002'} = 'ej0553';
$sitesTargeted{'1003'} = 'ej0553';
$sitesTargeted{'1007'} = 'ej0553';
my $inSitesTargeted = 0; # Counting subjects we care about.
for my $subjectId (sort keys %noDates) {
	my ($trialSiteId) = $subjectId =~ /^(....)....$/;
	die unless $trialSiteId;
	if (exists $sitesTargeted{$subjectId}) {
		$inSitesTargeted++;
	}
	for my $label (sort keys %{$noDates{$subjectId}}) {
		my $value = $noDates{$subjectId}->{$label} || "";
		print $out2 "$value;";
	}
	print $out2 "\n";
}
close $out2;
say "in sites of interest : $inSitesTargeted";