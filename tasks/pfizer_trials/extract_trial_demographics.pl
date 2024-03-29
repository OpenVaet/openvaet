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
my $outputFolder      = "public/doc/pfizer_trials";
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
my $patientsToNov14 = 0;
open my $out, '>:utf8', "$outputFolder/pfizer_trial_demographics.csv";
say $out "file;page number;entry number;patient id;sex;age (years);screening date;has HIV;is phase 1;";
for my $uniqueSubjectId (sort keys %patients) {
	my $sex           = $patients{$uniqueSubjectId}->{'sex'}           // die;
	my $year          = $patients{$uniqueSubjectId}->{'year'}          // die;
	my $month         = $patients{$uniqueSubjectId}->{'month'}         // die;
	my $ageYears      = $patients{$uniqueSubjectId}->{'ageYears'}      // die;
	my $hasHIV        = $patients{$uniqueSubjectId}->{'hasHIV'}        // die;
	my $isPhase1      = $patients{$uniqueSubjectId}->{'isPhase1'}      // die;
	my $pageNum       = $patients{$uniqueSubjectId}->{'pageNum'}       // die;
	my $entryNum      = $patients{$uniqueSubjectId}->{'entryNum'}      // die;
	my $screeningDate = $patients{$uniqueSubjectId}->{'screeningDate'} // die;
	say $out "pd-production-040122/125742_S1_M5_5351_c4591001-interim-mth6-demographics.pdf;$pageNum;$entryNum;$uniqueSubjectId;$sex;$ageYears;$screeningDate;$hasHIV;$isPhase1;";
	if ($screeningDate >= '20200720' && $screeningDate <= '20201114') {
		$patientsToNov14++;
	}
}
close $out;
say "patientsToNov14 : $patientsToNov14";

# Prints patients JSON.
open my $out3, '>:utf8', "$outputFolder/pfizer_trial_demographics.json";
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
		# p%patientsIds;
		for my $pNum (sort{$a <=> $b} keys %patientsIds) {
			die unless exists $patientsCharacteristics{$pNum} && exists $screeningDates{$pNum};
			my $uniqueSubjectId = $patientsIds{$pNum}->{'uniqueSubjectId'}      // die;
			my $subjectId       = $patientsIds{$pNum}->{'subjectId'}            // die;
			my $hasHIV          = $patientsIds{$pNum}->{'hasHIV'}               // die;
			my $isPhase1        = $patientsIds{$pNum}->{'isPhase1'}             // die;
			my $sex             = $patientsCharacteristics{$pNum}->{'sex'}      // die;
			my $ageYears        = $patientsCharacteristics{$pNum}->{'ageYears'} // die;
			my $screeningDate   = $screeningDates{$pNum}->{'screeningDate'}     // die;
			my $entryNum        = $patientsIds{$pNum}->{'entryNum'}             // die;
			my $year            = $screeningDates{$pNum}->{'year'}              // die;
			my $month           = $screeningDates{$pNum}->{'month'}             // die;
			my $weekNumber      = $screeningDates{$pNum}->{'weekNumber'}        // die;
			$totalPatients++;
			$patients{$subjectId}->{'pageNum'}         = $pageNum;
			$patients{$subjectId}->{'uniqueSubjectId'} = $uniqueSubjectId;
			$patients{$subjectId}->{'uniqueSubjectIds'}->{$uniqueSubjectId} = 1;
			$patients{$subjectId}->{'sex'}             = $sex;
			$patients{$subjectId}->{'hasHIV'}          = $hasHIV;
			$patients{$subjectId}->{'isPhase1'}        = $isPhase1;
			$patients{$subjectId}->{'ageYears'}        = $ageYears;
			$patients{$subjectId}->{'entryNum'}        = $entryNum;
			$patients{$subjectId}->{'weekNumber'}      = $weekNumber;
			$patients{$subjectId}->{'year'}            = $year;
			$patients{$subjectId}->{'month'}           = $month;
			$patients{$subjectId}->{'screeningDate'}   = $screeningDate;
		}
	}
}

sub parse_patients_ids {
	my @divs = @_;
	my %patientsIds = ();
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	my ($trialData, $siteData, $topMargin);
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		# say "$dNum | $text";
		my @words = split ' ', $text;
		next if $text =~ /Page /;
		for my $word (@words) {
			if (($word =~ /C4591001/ || $word =~ /^\d\d\d\d$/ || $word =~ /\d\d\d\d\d\d\d\d/)) {
				if ($word =~ /C4591001/) {
					unless ($word =~ /^C\d\d\d\d\d\d\d$/) {
						($word) = 'C4591001';
						# say "word : $word";
						# die;
					}
					my $style = $div->attr_get_i('style');
					($topMargin) = $style =~ /top:(.*)px;/;
					die unless looks_like_number $topMargin;
					$trialData = $word;
					$init++;
					# say "trialData : $trialData";
					# say "topMargin : $topMargin";
					# die;
				} elsif ($word =~ /^\d\d\d\d$/) {
					die "$word | $trialData && !$siteData" unless $trialData && !$siteData;
					$siteData = $word;
					# say "siteData  : $siteData";
					# die;
				} else {
					if ($trialData && $siteData) {
						my $uniqueSubjectId = "$trialData $siteData $word";
						my ($hasHIV, $isPhase1) = (0, 0);
						unless (length $uniqueSubjectId == 22) {
							if ($uniqueSubjectId =~ /\^/) {
								$isPhase1 = 1;
								$uniqueSubjectId =~ s/\^//;
							}
							if ($uniqueSubjectId =~ /†/) {
								$hasHIV = 1;
								$uniqueSubjectId =~ s/†//;
							}
							# say "uniqueSubjectId : [$uniqueSubjectId]";
							die unless (length $uniqueSubjectId == 22);
						}
						# die;
						$entryNum++;
						$patientsIds{$entryNum}->{'entryNum'}                 = $entryNum;
						$patientsIds{$entryNum}->{'uniqueSubjectId'}          = $uniqueSubjectId;
						$patientsIds{$entryNum}->{'subjectId'}                = $word;
						$patientsIds{$entryNum}->{'uniqueSubjectIdTopMargin'} = $topMargin;
						$patientsIds{$entryNum}->{'hasHIV'}                   = $hasHIV;
						$patientsIds{$entryNum}->{'isPhase1'}                 = $isPhase1;
						# say "$entryNum | $uniqueSubjectId";
						$trialData = undef;
						$siteData  = undef;
						$topMargin = undef;
					}
				}
			}
		}
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