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
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::stat;
use Date::DayOfWeek;
use Date::WeekNumber qw/ iso_week_number /;
use Scalar::Util qw(looks_like_number);
use File::Path qw(make_path);
use Math::Round qw(nearest);

# Original demographic files of the patients is here, page 22 to 3139.
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-fa-interim-demographics.pdf&currentLanguage=en
# This file resulted to 714 people in the Randomization file which weren't in the November 2020 file.
# Original demographic files of the patients is here, page 1 to 2951.
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-interim-mth6-demographics.pdf&currentLanguage=en
# This file has only 115 people missing.
# These subjects can be found "16.2.1.1 Listing of Subjects Discontinued From Vaccination and/or From the Study" (April 2021) in 
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-070122/125742_S1_M5_5351_c4591001-interim-mth6-discontinued-patients.pdf&currentLanguage=en

# This script parses this file, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $demographicPdfFile   = "public/pfizer_documents/native_files/pd-production-040122/125742_S1_M5_5351_c4591001-interim-mth6-demographics.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $demographicPdfFile;
my $demographicPdfFolder = "raw_data/pfizer_trials/demographic";
my $outputFolder      = "raw_data/pfizer_trials/demographic_output";
make_path($outputFolder) unless (-d $outputFolder);

# If the pdf hasn't been extracted already, proceeding.
unless (-d $demographicPdfFolder) {

	# Converts the Pfizer's PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$demographicPdfFile\" \"$demographicPdfFolder\"";
	system($pdfToHtmlCommand);
}

# We then verify that we have as expected 2951 HTML pages resulting from the extraction.
my %htmlPages = ();
verify_pdf_structure();

# We then extract pages 1 to 2951 (table "All Subjects").
my %patients = ();
my $totalPatients = 0;
extract_all_subjects_table();
# p%patients;
say "totalPatients   : $totalPatients";

# Generates weekly stats, prints .CSV.
my %stats = ();
my $patientsToSept6 = 0;
open my $out, '>:utf8', "$outputFolder/pfizer_trial_subjects.csv";
say $out "patient id;sex;age (years);screening date;week number;";
for my $patientId (sort keys %patients) {
	my $sex           = $patients{$patientId}->{'sex'}           // die;
	my $year          = $patients{$patientId}->{'year'}          // die;
	my $month         = $patients{$patientId}->{'month'}         // die;
	my $ageYears      = $patients{$patientId}->{'ageYears'}      // die;
	my $weekNumber    = $patients{$patientId}->{'weekNumber'}    // die;
	my $screeningDate = $patients{$patientId}->{'screeningDate'} // die;
	say $out "$patientId;$sex;$ageYears;$screeningDate;$weekNumber;";
	$stats{$weekNumber}->{'cases'}++;
	$stats{$weekNumber}->{'month'} = $month if !exists $stats{$weekNumber}->{'month'};
	if ($screeningDate >= '20200720' && $screeningDate <= '20200906') {
		$patientsToSept6++;
	}
}
close $out;
say "patientsToSept6 : $patientsToSept6";

# Prints weekly stats.
open my $out2, '>:utf8', "$outputFolder/weekly_recruitment.csv";
say $out2 "month;week number;cases;";
for my $weekNumber (sort{$a <=> $b} keys %stats) {
	my $cases = $stats{$weekNumber}->{'cases'} // die;
	my $month = $stats{$weekNumber}->{'month'} // die;
	say $out2 "$month;$weekNumber;$cases;";
}
close $out2;

# Prints patients JSON.
open my $out3, '>:utf8', "$outputFolder/pfizer_trial_subjects.json";
print $out3 encode_json\%patients;
close $out3;
# p%stats;

sub verify_pdf_structure {
	for my $htmlFile (glob "$demographicPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 2951) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_all_subjects_table {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		my $htmlFile = "$demographicPdfFolder/page$pageNum.html";
		say "htmlFile : $htmlFile";
		my $content;
		open my $in, '<:utf8', $htmlFile;
		while (<$in>) {
			$content .= $_;
		}
		close $in;
		die unless $content;
		my $tree = HTML::Tree->new();
		$tree->parse($content);
		my $body = $tree->find('body');
		my @divs = $body->find('div');

		# We first extract all the patient ids in the page, so we known how many to expect.
		my %patientsIds    = parse_patients_ids(@divs);
		my $pageTotalPatients = keys %patientsIds;
		die unless $pageTotalPatients;

		# We then look for age, sex.
		my %patientsCharacteristics = parse_patients_characteristics($pageTotalPatients, @divs);

		# We then look for screening date.
		my %screeningDates = ();
		my ($dNum, $pNum) = (0, 0);
		for my $div (@divs) {
			my $text = $div->as_trimmed_text;
			# say "$dNum | $text";
			# last if $text =~ /Note:/;
			$dNum++;
			if ($text =~ /^\d\d...2020$/) {
				$pNum++;
				my ($screeningDate, $year, $month, $weekNumber) = convert_date($text);
				$screeningDates{$pNum}->{'year'}          = $year;
				$screeningDates{$pNum}->{'month'}         = $month;
				$screeningDates{$pNum}->{'weekNumber'}    = $weekNumber;
				$screeningDates{$pNum}->{'screeningDate'} = $screeningDate;
			}
		}
		unless ($pNum == $pageTotalPatients) {
			die "$pNum != $pageTotalPatients";
		}

		# And then load the data in the final table.
		for my $pNum (sort{$a <=> $b} keys %patientsIds) {
			die unless exists $patientsCharacteristics{$pNum} && exists $screeningDates{$pNum};
			my $patientId     = $patientsIds{$pNum}->{'patientId'}            // die;
			my $hasHIV        = $patientsIds{$pNum}->{'hasHIV'}               // die;
			my $isPhase1      = $patientsIds{$pNum}->{'isPhase1'}             // die;
			my $sex           = $patientsCharacteristics{$pNum}->{'sex'}      // die;
			my $ageYears      = $patientsCharacteristics{$pNum}->{'ageYears'} // die;
			my $screeningDate = $screeningDates{$pNum}->{'screeningDate'}     // die;
			my $year          = $screeningDates{$pNum}->{'year'}              // die;
			my $month         = $screeningDates{$pNum}->{'month'}             // die;
			my $weekNumber    = $screeningDates{$pNum}->{'weekNumber'}        // die;
			$totalPatients++;
			$patients{$patientId}->{'pageNum'}       = $pageNum;
			$patients{$patientId}->{'sex'}           = $sex;
			$patients{$patientId}->{'hasHIV'}        = $hasHIV;
			$patients{$patientId}->{'isPhase1'}      = $isPhase1;
			$patients{$patientId}->{'ageYears'}      = $ageYears;
			$patients{$patientId}->{'weekNumber'}    = $weekNumber;
			$patients{$patientId}->{'year'}          = $year;
			$patients{$patientId}->{'month'}         = $month;
			$patients{$patientId}->{'screeningDate'} = $screeningDate;
		}
	}
}

sub parse_patients_ids {
	my @divs = @_;
	my %patientsIds = ();
	my ($dNum, $pNum, $init) = (0, 0, 0);
	my $trialAndSiteData;
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		# say "$dNum | [$text]";
		if (($text =~ /C4591001/ || $text =~ /\d\d\d\d\d\d\d\d/)) {
			if ($text =~ /C4591001/) {
				# say "text : $text";
				unless ($text =~ /^C\d\d\d\d\d\d\d \d\d\d\d$/) {
					($text) = $text =~ /(C\d\d\d\d\d\d\d \d\d\d\d)/;
					# say "text : $text";
					die unless $text;
				}
				$trialAndSiteData = $text;
				$init++;
				# say "trialAndSiteData : $trialAndSiteData";
			} else {
				# say "text : $text";
				if ($trialAndSiteData) {
					my $patientId = "$trialAndSiteData $text";
					my ($hasHIV, $isPhase1) = (0, 0);
					unless (length $patientId == 22) {
						if ($patientId =~ /\^/) {
							$isPhase1 = 1;
							$patientId =~ s/\^//;
						}
						if ($patientId =~ /†/) {
							$hasHIV = 1;
							$patientId =~ s/†//;
						}
						# say "patientId : [$patientId]";
						die unless (length $patientId == 22);
					}
					# die;
					$trialAndSiteData = undef;
					$pNum++;
					$patientsIds{$pNum}->{'patientId'} = $patientId;
					$patientsIds{$pNum}->{'hasHIV'}    = $hasHIV;
					$patientsIds{$pNum}->{'isPhase1'}  = $isPhase1;
					# say "$pNum | $patientId";
				}
			}
		}
	}
	unless ($init == keys %patientsIds) {
		p%patientsIds;
		die "$init != " . keys %patientsIds;
	}
	return %patientsIds;
}

sub parse_patients_characteristics {
	my ($pageTotalPatients, @divs) = @_;
	my %patientsCharacteristics = ();
	my ($dNum, $pNum) = (0, 0);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		# say "$dNum | $text";
		if ($text =~ / Male/ || $text =~ / Female/) {
			$pNum++;
			my ($ageYears, $sex);
			if ($text =~ / Male/) {
				$sex = 'Male';
				($ageYears) = $text =~ /(.*) Male/;
			} elsif ($text =~ / Female/) {
				$sex = 'Female';
				($ageYears) = $text =~ /(.*) Female/;
			}
			if ($ageYears =~ / /) {
				my @elems = split ' ', $ageYears;
				$ageYears = $elems[scalar @elems - 1] // die;
			}
			die "text : [$text], ageYears : [$ageYears]" unless $ageYears && looks_like_number $ageYears;
			$patientsCharacteristics{$pNum}->{'sex'}      = $sex;
			$patientsCharacteristics{$pNum}->{'ageYears'} = $ageYears;
			# say "$pNum | $text -> $sex, $ageYears";
		}
	}
	unless ($pNum == $pageTotalPatients) {
		die "$pNum != $pageTotalPatients";
	}
	return %patientsCharacteristics;
}

sub convert_date {
	my $dt = shift;
	my ($d, $m, $y) = $dt =~ /(..)(...)(....)/;
	$m = convert_month($m);
	my $weekNumber = iso_week_number("$y-$m-$d");
	(undef, $weekNumber) = split '-', $weekNumber;
	$weekNumber =~ s/W//;
	return ("$y$m$d", $y, $m, $weekNumber);
}

sub convert_month {
	my $m = shift;
	return '01' if $m eq 'JAN';
	return '02' if $m eq 'FEB';
	return '03' if $m eq 'MAR';
	return '04' if $m eq 'APR';
	return '05' if $m eq 'MAY';
	return '06' if $m eq 'JUN';
	return '07' if $m eq 'JUL';
	return '08' if $m eq 'AUG';
	return '09' if $m eq 'SEP';
	return '10' if $m eq 'OCT';
	return '11' if $m eq 'NOV';
	return '12' if $m eq 'DEC';
	die "failed to convert month";
}