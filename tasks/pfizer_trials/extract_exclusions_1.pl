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

# Exclusions are stored in tables contained in this document:
# https://openvaet.org/pfizearch/viewer?pdf=pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-excluded-patients-sensitive.pdf&currentLanguage=en
# This script parses the first table, converts the PDF to HTML, then parses the HTML to convert it to a usable JSON format.

# We first parse the PDF file (which must be located here, which means that you must run tasks/pfizer_documents/get_documents.pl first).
my $exclusionsPdfFile   = "public/pfizer_documents/native_files/pd-production-030122/125742_S1_M5_5351_c4591001-fa-interim-excluded-patients-sensitive.pdf";
die "Missing source file, please run tasks/pfizer_documents/get_documents.pl first." unless -f $exclusionsPdfFile;
my $exclusionsPdfFolder = "raw_data/pfizer_trials/exclusions_pdf";
my $outputFolder        = "public/doc/pfizer_trials";
make_path($outputFolder) unless (-d $outputFolder);

# If the pdf hasn't been extracted already, proceeding.
unless (-d $exclusionsPdfFolder) {

	# Converts the Pfizer's PDFs to HTML.
	# You'll need the XPDF version corresponding to your OS.
	# Both files below are coming from https://www.xpdfreader.com/download.html
	# Windows : https://dl.xpdfreader.com/xpdf-tools-win-4.04.zip
	# Linux   : https://dl.xpdfreader.com/xpdf-tools-linux-4.04.tar.gz
	# Place the "pdftohtml.exe" (windows) or "pdftohtml" (linux) file,
	# located in the bin32/64 subfolder of the archive you downloaded,
	# in your project repository.
	my $pdfToHtmlExecutable = 'pdftohtml.exe'; # Either pdftohtml or pdftohtml.exe, depending on your OS.
	my $pdfToHtmlCommand     = "$pdfToHtmlExecutable \"$exclusionsPdfFile\" \"$exclusionsPdfFolder\"";
	system($pdfToHtmlCommand);
}

# We then verify that we have as expected 4376 HTML pages resulting from the extraction.
my %htmlPages = ();
verify_pdf_structure();

# We then extract pages 22 to 4376 (table "All Subjects").
my %patients        = ();
my %patientsByPages = ();
my $totalPatients   = 0;
extract_patient_ids();
say "total subjects rows in this exclusion table   : [$totalPatients]";
extract_patient_data();
my $totalSubjects   = keys %patients;
say "total unique subjects in this exclusion table : [" . $totalSubjects . "]";

# Prints patients JSON.
open my $out, '>:utf8', "$outputFolder/pfizer_trial_exclusions_1.json";
print $out encode_json\%patients;
close $out;

sub verify_pdf_structure {
	for my $htmlFile (glob "$exclusionsPdfFolder/*") {
		next unless $htmlFile =~ /\/page.*\.html/;
		my ($pageNum) = $htmlFile =~ /\/page(.*)\.html/;
		$htmlPages{$pageNum} = 1;
	}
	unless (keys %htmlPages == 1448) {
		die "Something went wrong during PDF extraction. Please verify your PDF file & that XPDF is properly configured.";
	}
}

sub extract_patient_ids {
	for my $pageNum (sort{$a <=> $b} keys %htmlPages) {
		my $htmlFile = "$exclusionsPdfFolder/page$pageNum.html";
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
		my %patientsIds = parse_patients_ids(@divs);

		# Integrates subjects by pages.
		for my $topMargin (sort{$a <=> $b} keys %patientsIds) {
			my $nextTopMargin;
			for my $nTM (sort{$a <=> $b} keys %patientsIds) {
				next if $nTM <= $topMargin;
				$nextTopMargin = $nTM;
				last;
			}
			$totalPatients++;
			my $uSubjectId = $patientsIds{$topMargin}->{'uSubjectId'} // die;
			my ($subjectId)       = $uSubjectId =~ /^C4591001 .... (.*)$/;
			die unless $subjectId && $subjectId =~ /^........$/;
			die unless $uSubjectId =~ /$subjectId$/;
			my $entryNum   = $patientsIds{$topMargin}->{'entryNum'}   // die;
			$patientsByPages{$pageNum}->{$entryNum}->{'pageNum'}   = $pageNum;
			$patientsByPages{$pageNum}->{$entryNum}->{'subjectId'} = $subjectId;
			$patientsByPages{$pageNum}->{$entryNum}->{'topMargin'} = $topMargin;
		}
		last if $pageNum == 643;
	}
}

sub parse_patients_ids {
	my @divs = @_;
	my ($dNum, $entryNum, $init) = (0, 0, 0);
	my ($trialData, $siteData, $topMargin);
	my %patientsIds = ();
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /Note:/;
		$dNum++;
		my @words = split ' ', $text;
		for my $word (@words) {
			if (($word =~ /C4591001/ || $word =~ /^\d\d\d\d$/ || $word =~ /\d\d\d\d\d\d\d\d/)) {
				if ($word =~ /C4591001/) {
					unless ($word =~ /^C\d\d\d\d\d\d\d$/) {
						($word) = 'C4591001';
					}
					my $style = $div->attr_get_i('style');
					($topMargin) = $style =~ /top:(.*)px;/;
					die unless looks_like_number $topMargin;
					$trialData = $word;
					$init++;
				} elsif ($word =~ /^\d\d\d\d$/) {
					next unless $trialData && !$siteData;
					$siteData = $word;
				} else {
					if ($trialData && $siteData) {
						my $uSubjectId = "$trialData $siteData $word";
						$uSubjectId =~ s/\^//;
						unless (length $uSubjectId == 22) {
							$uSubjectId =~ s/†//;
							unless (length $uSubjectId == 22) {
								($uSubjectId) = split ' \(', $uSubjectId;
								die "uSubjectId : [$uSubjectId]" unless (length $uSubjectId == 22);
							}
						}
						$entryNum++;
						$patientsIds{$topMargin}->{'entryNum'}           = $entryNum;
						$patientsIds{$topMargin}->{'uSubjectId'}          = $uSubjectId;
						$patientsIds{$topMargin}->{'uSubjectIdTopMargin'} = $topMargin;
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

sub parse_exclusions_data {
	my ($pageTotalPatients, @divs) = @_;
	my %structure = ();
	my %exclusionsData = ();
	my ($dNum, $entryNum) = (0, 0);
	# p%patientsIds;
	# die;

	# For each subject, parsing data between from page, from top, to page, to top.
	for my $div (@divs) {
		my $text = $div->as_trimmed_text;
		last if $text =~ /FDA-CBER-/;
		$dNum++;
		my $style = $div->attr_get_i('style');
		my ($topMargin) = $style =~ /top:(.*)px;/;
		my ($leftMargin) = $style =~ /left:(.*)px; top:/;
		die unless looks_like_number $topMargin;
		die unless looks_like_number $leftMargin;
		$structure{$topMargin}->{'totalMarginLeft'} += $leftMargin;
		my $totalMarginLeft = $structure{$topMargin}->{'totalMarginLeft'} // die;
		# next unless $leftMargin > 120 && $leftMargin < 250;

		say "$topMargin - $totalMarginLeft -> $text";
	}
	die;
	return %exclusionsData;
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
	$m = uc $m;
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
	die "failed to convert month [$m]";
}

