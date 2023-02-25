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

my $dt19600101       = '1960-01-01 12:00:00';
my $tp19600101       = time::datetime_to_timestamp($dt19600101);
my $excludedFile     = "raw_data/pfizer_trials/16_2_3_1.csv";
die "you must convert the excluded file using readstats and place it in [raw_data/pfizer_trials/16_2_3_1.csv] first." unless -f $excludedFile;
open my $in, '<:utf8', $excludedFile;
my %dataLabels       = ();
my ($dRNum,
	$expectedValues) = (0, 0);
my %subjects         = ();
my %stats            = ();
my %subjectsByArms   = ();
my ($arm, $subjectId);
open my $out, '>:utf8', '125742_S1_M5_5351_c4591001-fa-interim-excluded-patients-sensitive_table_16_2_3_1.csv';
say $out "Unique Subject Id;SubjectId;Arm;Population;Motive;";
while (<$in>) {
	$dRNum++;

	# Verifying line.
	my $line = $_;
	$line = decode("ascii", $line);
	for (/[^\n -~]/g) {
	    printf "Bad character: %02x\n", ord $_;
	    die;
	}

	# Verifying we have the expected number of values.
	my @row = split ";", $_;
	my $vN  = 0;
	my %values = ();
	for my $value (@row) {
		$vN++;
		$values{$vN} = $value;
	}
	die unless (keys %values == 12);
	$arm = $values{'2'} // die;
	my $uSubjectId  = $values{'6'} // die;
	($subjectId)    = $uSubjectId =~ /^C4591001 .... (.*)$/;
	next unless $subjectId && $subjectId =~ /^........$/;
	die unless $uSubjectId =~ /$subjectId$/;
	my $population  = $values{'7'} // die;
	my $motive      = $values{'8'} // die;
	$motive =~ s/^ //;
	$subjects{$subjectId}->{'arm'} = $arm;
	die if exists $subjects{$subjectId}->{'populations'}->{$population};
	$subjects{$subjectId}->{'populations'}->{$population} = $motive;
	say $out "$uSubjectId;$subjectId;$arm;$population;$motive;";
	# say "arm        : $arm";
	# say "subjectId  : $subjectId";
	# say "population : $population";
	# say "motive     : $motive";
	if ($population eq 'Evaluable efficacy (7 days)') {
		if (
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1).' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  did not  receive all vaccinations as randomized or did not receive Dose 2  within the predefined window (19-42 days after Dose 1).' ||
			$motive eq 'Randomized but did not meet all eligibility criteria. ' ||
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1).    '
		) {
			$stats{'7 days'}->{'doseRelatedExclusion'}->{$arm}->{'total'}++;
		} elsif (
			$motive eq 'Had other important protocol deviations on or prior to 7 days  after Dose 2.' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  did not  receive all vaccinations as randomized or did not receive Dose 2  within the predefined window (19-42 days after Dose 1),  had  other important protocol deviations on or prior to 7 days after  Dose 2.' ||
			$motive eq 'Did not provide informed consent,  had other important protocol  deviations on or prior to 7 days after Dose 2.' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  had other  important protocol deviations on or prior to 7 days after Dose 2.' ||
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1),    had other important protocol deviations on or prior to 7 days after   Dose 2.' ||
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1),   had other important protocol deviations on or prior to 7 days after  Dose 2.' ||
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1),   had other important protocol deviations on or prior to 14 days  after Dose 2.' ||
			$motive eq 'Had other important protocol deviations on or prior to 14 days  after Dose 2.' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  did not  receive all vaccinations as randomized or did not receive Dose 2  within the predefined window (19-42 days after Dose 1),  had  other important protocol deviations on or prior to 14 days after  Dose 2.' ||
			$motive eq 'Did not provide informed consent,  had other important protocol  deviations on or prior to 14 days after Dose 2.' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  had other  important protocol deviations on or prior to 14 days after Dose 2.'
		) {
			$stats{'7 days'}->{'otherImportantExclusion'}->{$arm}->{'total'}++;
			$stats{'7 days'}->{'otherImportantExclusion'}->{$arm}->{'subjects'}->{$subjectId} = 1;
			$subjectsByArms{$arm}->{$subjectId}->{'7 days'} = $motive;
		} else {
			die "motive : [$motive]";
		}
	} elsif ($population eq 'Evaluable efficacy (14 days)') {
		if (
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1).' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  did not  receive all vaccinations as randomized or did not receive Dose 2  within the predefined window (19-42 days after Dose 1).' ||
			$motive eq 'Randomized but did not meet all eligibility criteria. ' ||
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1).    '
		) {
			$stats{'14 days'}->{'doseRelatedExclusion'}->{$arm}->{'total'}++;
		} elsif (
			$motive eq 'Had other important protocol deviations on or prior to 7 days  after Dose 2.' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  did not  receive all vaccinations as randomized or did not receive Dose 2  within the predefined window (19-42 days after Dose 1),  had  other important protocol deviations on or prior to 7 days after  Dose 2.' ||
			$motive eq 'Did not provide informed consent,  had other important protocol  deviations on or prior to 7 days after Dose 2.' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  had other  important protocol deviations on or prior to 7 days after Dose 2.' ||
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1),    had other important protocol deviations on or prior to 7 days after   Dose 2.' ||
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1),   had other important protocol deviations on or prior to 7 days after  Dose 2.' ||
			$motive eq 'Did not receive all vaccinations as randomized or did not receive  Dose 2 within the predefined window (19-42 days after Dose 1),   had other important protocol deviations on or prior to 14 days  after Dose 2.' ||
			$motive eq 'Had other important protocol deviations on or prior to 14 days  after Dose 2.' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  did not  receive all vaccinations as randomized or did not receive Dose 2  within the predefined window (19-42 days after Dose 1),  had  other important protocol deviations on or prior to 14 days after  Dose 2.' ||
			$motive eq 'Did not provide informed consent,  had other important protocol  deviations on or prior to 14 days after Dose 2.' ||
			$motive eq 'Randomized but did not meet all eligibility criteria,  had other  important protocol deviations on or prior to 14 days after Dose 2.'
		) {
			$stats{'14 days'}->{'otherImportantExclusion'}->{$arm}->{'total'}++;
			$stats{'14 days'}->{'otherImportantExclusion'}->{$arm}->{'subjects'}->{$subjectId} = 1;
			$subjectsByArms{$arm}->{$subjectId}->{'14 days'} = $motive;
		} else {
			die "motive : [$motive]";
		}
	} else {
		next;
	}
}
close $out;
close $in;
say "dRNum           : $dRNum";
say "patients        : " . keys %subjects;
p%stats;

# Verifies that each subject is featured at 14 days if featured at 7 days.
for my $arm (sort keys %{$stats{'7 days'}->{'otherImportantExclusion'}}) {
	for my $subjectId (sort{$a <=> $b} keys %{$stats{'7 days'}->{'otherImportantExclusion'}->{$arm}->{'subjects'}}) {
		unless (exists $stats{'14 days'}->{'otherImportantExclusion'}->{$arm}->{'subjects'}->{$subjectId}) {
			say "subject [$subjectId] in the [$arm] arm is excluded at 7 days but not at 14 days.";
		}
	}
}

my $outputFolder   = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# Prints patients JSON.
open my $out2, '>:utf8', "$outputFolder/pfizer_excluded_patients.json";
print $out2 encode_json\%subjects;
close $out2;

# Prints XLSX synthesis on the "Other exclusion" details.
open my $out3, '>:utf8', '125742_S1_M5_5351_c4591001-fa-interim-excluded-patients-sensitive_table_16_2_3_1_other_exclusions.csv';
say $out3 "Arm;SubjectId;Excluded At 7 Days;Excluded At 14 Days;Excluded At 7 Days (Motive);Excluded At 14 Days (Motive);";
for my $arm (sort keys %subjectsByArms) {
	for my $subjectId (sort{$a <=> $b} keys %{$subjectsByArms{$arm}}) {
		my ($excludedAt7Days, $excludedAt7DaysMotive) = ('No', '');
		if (exists $subjectsByArms{$arm}->{$subjectId}->{'7 days'}) {
			$excludedAt7Days = 'Yes';
			$excludedAt7DaysMotive = $subjectsByArms{$arm}->{$subjectId}->{'7 days'} // die;
		}
		my ($excludedAt14Days, $excludedAt14DaysMotive) = ('No', '');
		if (exists $subjectsByArms{$arm}->{$subjectId}->{'14 days'}) {
			$excludedAt14Days = 'Yes';
			$excludedAt14DaysMotive = $subjectsByArms{$arm}->{$subjectId}->{'14 days'} // die;
		}
		say $out3 "$arm;$subjectId;$excludedAt7Days;$excludedAt14Days;$excludedAt7DaysMotive;$excludedAt14DaysMotive;";
	}
}
close $out3;
