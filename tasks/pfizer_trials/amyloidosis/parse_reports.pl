#!/usr/bin/perl
use strict;
use warnings;
use LWP::UserAgent;
use File::Basename;
use JSON;
use 5.26.0;
use HTTP::Request::Common qw(POST);
use Data::Printer;
use File::Slurp;
use File::Path qw(make_path);

my %path         = ();
my $nomF         = 'tasks/pfizer_trials/amyloidosis/nomenclature.csv';
my $url          = "http://163.172.57.240:5503/aws";
my $tot          = 0;
my %data         = ();
my $outputFolder = "tasks/pfizer_trials/amyloidosis/cd4cd8";
make_path($outputFolder) unless (-d $outputFolder);
load_nomenclature();
process_data_ocr();

sub load_nomenclature {
	open my $in, '<:utf8', $nomF;
	my $formerLabel;
	while (<$in>) {
		chomp $_;
		my ($label, $cdRef, $start0235, $end0235, $start0241, $end0241) = split ';', $_;
		next if $start0235 eq '0235 start';
		if ($label) {
			$formerLabel = $label;
		}
		$tot++;
		$path{$formerLabel}->{$cdRef}->{'start0235'} = $start0235;
		$path{$formerLabel}->{$cdRef}->{'end0235'}   = $end0235;
		$path{$formerLabel}->{$cdRef}->{'start0241'} = $start0241;
		$path{$formerLabel}->{$cdRef}->{'end0241'}   = $end0241;
	}
	close $in;
}

sub process_data_ocr {
	my $cpt = 0;
	for my $label (sort keys %path) {
		for my $cdRef (sort keys %{$path{$label}}) {
			$cpt++;
			my $start0235 = $path{$label}->{$cdRef}->{'start0235'} // die;
			my $end0235   = $path{$label}->{$cdRef}->{'end0235'}   // die;
			my $start0241 = $path{$label}->{$cdRef}->{'start0241'} // die;
			my $end0241   = $path{$label}->{$cdRef}->{'end0241'}   // die;
			my $rowNum    = 0;
			my %structure = ();
			for my $page ($start0235 .. $end0235) {
				say "Processing [$label - $cdRef] - [$page]";
				my $file  = "tasks/pfizer_trials/amyloidosis/raw/$page.png";
				die "File not found: $file" unless -f $file;

				my $pathImg  = $file;

				my $img      = read_file($pathImg, binmode => ':raw') or die "Couldn't read $pathImg: $!";

				my $filename = basename($file);
				my $ua       = LWP::UserAgent->new;

				my $request  = POST(
				    $url,
				    Content_Type => 'form-data',
				    Content => [
				        file => [
				            $pathImg,
				            $filename,
				            Content => $img,
				            'Content-Type' => 'image/png',
				            'Content-Disposition' => qq(form-data; name="file"; filename="$filename")
				        ]
				    ]
				);

				my $response = $ua->request($request);

				if ($response->is_success) {
				    my $json = decode_json($response->decoded_content);
				    my @data = @{%$json{'table'}};
				    for my $rowData (@data) {
				    	# p$rowData;
				    	my $column = %$rowData{'cell'}->{'column'} // die;
				    	my $row    = %$rowData{'cell'}->{'row'}    // die;
				    	my $text   = %$rowData{'cell'}->{'text'}   // die;
				    	if ($text =~ /^.*/) {
				    		$text =~ s/ //;
				    	}
				    	if ($row == 1 || $row == 2) { # If we have no table yet for this table, creating it.
				    		unless (exists $data{$label}->{$cdRef}->{'headers'}->{$row}->{$column}) {
					    		$data{$label}->{$cdRef}->{'headers'}->{$row}->{$column} = $text;
				    		}
				    	} else {
				    		unless (exists $structure{$label}->{$cdRef}->{$page}->{$row}) {
				    			$rowNum++;
				    			$structure{$label}->{$cdRef}->{$page}->{$row} = $rowNum;
				    		}
				    		my $rNum = $structure{$label}->{$cdRef}->{$page}->{$row} // die;
				    		$data{$label}->{$cdRef}->{'rows'}->{$rNum}->{$column} = $text;
				    		# say "column : $column";
				    		# say "text   : $text";
				    	}
				    }
				    # p$json;
				    # die;
				}
				else {
					die;
				}
			}

			open my $out, '>:utf8', "$outputFolder/$label - $cdRef.csv";
			for my $headersRow (sort{$a <=> $b} keys %{$data{$label}->{$cdRef}->{'headers'}}) {
				my $topLetter  = 'J';
				if ($cdRef eq 'CD8') {
					$topLetter = 'H';
				}
				for my $column ('B' .. $topLetter) {
					my $value = $data{$label}->{$cdRef}->{'headers'}->{$headersRow}->{$column} // '';
					print $out "$value;";
					# say "column : $column";
				}
				say $out '';
			}
			for my $rowNum (sort{$a <=> $b} keys %{$data{$label}->{$cdRef}->{'rows'}}) {
				my $topLetter  = 'J';
				if ($cdRef eq 'CD8') {
					$topLetter = 'H';
				}
				for my $column ('B' .. $topLetter) {
					my $value = $data{$label}->{$cdRef}->{'rows'}->{$rowNum}->{$column} // '';
					print $out "$value;";
					# say "column : $column";
				}
				say $out '';
			}
			close $out;
			# p%data;
			# die;
		}
	}
}
