#!/usr/bin/perl
use strict;
use warnings;
use 5.30.0;
binmode STDOUT, ":utf8";
use utf8;

# Cpan dependencies.
no autovivification;
use Data::Printer;
use Data::Dumper;
use JSON;
use File::Path qw(make_path);

# Project's libraries.
use FindBin;
use lib "$FindBin::Bin/../../lib";
use time;
use global;

# API limits        : https://developer.twitter.com/en/portal/products
# Twitter tutorials : https://developer.twitter.com/en/docs/tutorials
# Postman API V2    : https://www.postman.com/twitter/workspace/twitter-s-public-workspace/collection/9956214-784efcda-ed4c-4491-a4c0-a26470a67400?ctx=documentation

# Fetching configuration required (twitter bearer token).
my $twitterTweetsFolder  = 'social_networks_data/twitter';
my $configurationFile    = 'tasks/social_networks/config.cfg';
my $forwardedTweetsFile  = 'social_networks_data/twitter_tweets_forwarded.json'; 
my $summaryFile          = 'social_networks_data/summary.json'; 

# Loading texts already transfered.
my %textsForwarded  = ();
my @forwardedTweets = ();
my %summaryStats    = ();
if (-f $summaryFile) {
	my $json = json_from_file($summaryFile);
	%summaryStats = %$json;
}
if (-f $forwardedTweetsFile) {
	$summaryStats{'Twitter'}->{'toReview'} = 0;
	my $json = json_from_file($forwardedTweetsFile);
	@forwardedTweets = @$json;
	for my $fileData (@$json) {
		my $text = %$fileData{'text'} // die;
		my $review = %$fileData{'review'} // die;
		$summaryStats{'Twitter'}->{'toReview'}++ if !$review;
		$textsForwarded{$text} = 1;

	}
}

my %keywords = ();
load_keywords();

scan_tweets();

sub json_from_file {
    my $file = shift;
    if (-f $file) {
        my $json;
        eval {
            open my $in, '<:utf8', $file;
            while (<$in>) {
                $json .= $_;
            }
            close $in;
            $json = decode_json($json) or die $!;
        };
        if ($@) {
            {
                local $/;
                open (my $fh, $file) or die $!;
                $json = <$fh>;
                close $fh;
            }
            eval {
                $json = decode_json($json);
            };
            if ($@) {
                die "failed parsing json : " . @!;
            }
        }
        return $json;
    } else {
        return {};
    }
}

sub load_keywords {
    my $sTb = $dbh->selectall_hashref("SELECT id as rsKeywordsSetId, keywords FROM rs_keywords_set", 'rsKeywordsSetId');
    for my $rsKeywordsSetId (sort{$a <=> $b} keys %$sTb) {
	    my $keywordsFiltered = %$sTb{$rsKeywordsSetId}->{'keywords'} // die;
	    my @keywordsFiltered = split '<br \/>', $keywordsFiltered;
	    for my $keyword (@keywordsFiltered) {
	        my $lcKeyword = lc $keyword;
	        if ($lcKeyword =~ /^-.*/) {
	        	$keywords{'excluded'}->{$lcKeyword} = 1;
	        } else {
	        	$keywords{'included'}->{$lcKeyword} = 1;
	        }
	    }
    }
}

sub scan_tweets {
	# say"Indexing Tweets ...";
	my $fromUts = 1665464425;
	my %keywordTweets = ();
	for my $keywordFile (glob "$twitterTweetsFolder/*") {
		my ($keyword) = $keywordFile =~ /$twitterTweetsFolder\/(.*)/;
		my %timestamps = ();
		for my $createdOnFolder (glob "$twitterTweetsFolder/$keyword/*") {
			my ($createdOn) = $createdOnFolder =~ /$twitterTweetsFolder\/$keyword\/(.*)/;
			next if $createdOn < $fromUts;
			$timestamps{$createdOn} = 1;
		}
		for my $createdOn (sort{$a <=> $b} keys %timestamps) {
			for my $tweetFile (glob "$twitterTweetsFolder/$keyword/$createdOn/*") {
				my ($tweetId) = $tweetFile =~ /$twitterTweetsFolder\/$keyword\/$createdOn\/(.*)\.json/;
				$keywordTweets{$tweetId}->{'createdOn'} = $createdOn;
				$keywordTweets{$tweetId}->{'tweetFile'} = $tweetFile;
				$keywordTweets{$tweetId}->{'keywords'}->{$keyword} = 1;
				# say "tweetId : $tweetId";
			}
		}
	}
	for my $tweetId (sort{$a <=> $b} keys %keywordTweets) {
		my $totalKeywords = keys %{$keywordTweets{$tweetId}->{'keywords'}};
		if ($totalKeywords > 1 && exists $keywordTweets{$tweetId}->{'keywords'}->{'russia'}) {
			my $tweetFile      = $keywordTweets{$tweetId}->{'tweetFile'} // die;
			my $createdOn      = $keywordTweets{$tweetId}->{'createdOn'} // die;
	        my $json           = json_from_file($tweetFile);
	        my $conversationId = %$json{'conversation_id'} // die;
	        my $text           = %$json{'text'} // die;
	        my %obj            = %$json;
	        my $authorId         = $obj{'author_id'}  // die;
	        my $creationDatetime = $obj{'created_at'} // die;
	        my ($creationDate, $creationHour) = split 'T', $creationDatetime;
	        ($creationHour) = split '\.', $creationHour;
	        $text =~ s/\n/ <br>/g;
	        if (exists $obj{'entities'}->{'urls'}) {
	            my $refEntities = \@{$obj{'entities'}->{'urls'}};
	            my @refEntities = @$refEntities;
	            for my $uO (@refEntities) {
	                my $url         = %$uO{'url'}          // die;
	                my $displayUrl  = %$uO{'display_url'}  // die;
	                my $expandedUrl = %$uO{'expanded_url'} // die;
	                $text =~ s/$url/<a href=\"$expandedUrl\" target=\"_blank\">$displayUrl<\/a>/g;
	            }
	        }
	        unless (exists $textsForwarded{$text}) {
	        	$textsForwarded{$text} = 1;
		        my $tweetUrl = "https://twitter.com/$authorId/status/$tweetId";
				# say "tweetId : $tweetId, tweetUrl : $tweetUrl, totalKeywords : $totalKeywords, createdOn : $createdOn, text : $text";
				my %o = ();
				$o{'authorId'} = $authorId;
				$o{'id'} = $tweetId;
				$o{'createdOn'} = $createdOn;
				$o{'review'} = 0;
				$o{'forward'} = 0;
				$o{'totalKeywords'} = $totalKeywords;
				$o{'text'} = $text;
				$o{'url'} = $tweetUrl;
				$o{'conversationId'} = $conversationId;
				$o{'file'} = $tweetFile;
				$o{'creationDatetime'} = $creationDatetime;
				for my $keyword (sort keys %{$keywordTweets{$tweetId}->{'keywords'}}) {
					$o{'keywords'}->{$keyword} = 1;
				}
				push @forwardedTweets, \%o;
				$summaryStats{'Twitter'}->{'toReview'}++;
	        }
			# die;
		}
	}

	open my $out1, '>:utf8', $forwardedTweetsFile or die $!;
	print $out1 encode_json\@forwardedTweets;
	close $out1;

	open my $out2, '>:utf8', $summaryFile or die $!;
	print $out2 encode_json\%summaryStats;
	close $out2;
}