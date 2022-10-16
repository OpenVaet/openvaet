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
use HTTP::Cookies;
use HTML::Tree;
use LWP::UserAgent;
use LWP::Simple;
use File::Path qw(make_path);
use HTTP::Cookies qw();
use HTTP::Request::Common qw(POST OPTIONS);
use HTTP::Headers;
use Hash::Merge;
use Scalar::Util qw(looks_like_number);
use Digest::MD5  qw(md5 md5_hex md5_base64);

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

make_path($twitterTweetsFolder)
    unless (-d $twitterTweetsFolder);
my $configurationFile    = 'tasks/social_networks/config.cfg';
my %config            = ();
get_config();
my $twitterBearerToken   = $config{'twitterBearerToken'}        || die;

# UA used to scrap target.
my $cookie               = HTTP::Cookies->new();
my $ua                   = LWP::UserAgent->new
(
    timeout              => 30,
    cookie_jar           => $cookie,
    agent                => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
);
my @headers = (
    'Authorization'      => 'Bearer ' . $twitterBearerToken,
    'Accept'             => '*/*',
    'Accept-Encoding'    => 'gzip, deflate, br',
    'Connection'         => 'keep-alive'
);

# Initiates values stored.
my $maxTweetsResults     = 100;       # Defines how many tweets we will get by query
my $sleepSecondsOnFail   = 10;        # Defines how long we will sleep on a failed query.
my $sleepSeconds         = 900;       # Defines how long we will sleep on a "Too Many Requests" server reply.
my $delayBetweenUpdates  = 3600 * 1;  # Time we wait (in seconds) between followers updates on a given profile.

my %keywords = ();
load_keywords();

my ($current, $total) = (0, 0);
$total = keys %{$keywords{'included'}};
for my $keyword (sort keys %{$keywords{'included'}}) {
	$current++;
	my $latestTweetId = latest_keyword_tweet_id($keyword);
	search_tweets($keyword, $current, $total, $latestTweetId, undef);
}


sub get_config {
    die "missing file [$configurationFile]" unless -f $configurationFile;
    my $json   = json_from_file($configurationFile);
    %config = %$json;
}

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

sub latest_keyword_tweet_id {
	my ($keyword) = shift;
	my $latestTweetId;
	if (-d "$twitterTweetsFolder/$keyword") {
		my $createdOn;
		my %timestamps = ();
		for my $createdOnFolder (glob "$twitterTweetsFolder/$keyword/*") {
			($createdOn) = $createdOnFolder =~ /$twitterTweetsFolder\/$keyword\/(.*)/;
			$timestamps{$createdOn} = 1;
		}
		for my $timestamp (sort{$b <=> $a} keys %timestamps) {
			$createdOn = $timestamp;
			last;
		}
		for my $tweetFile (glob "$twitterTweetsFolder/$keyword/$createdOn/*") {
			($latestTweetId) = $tweetFile =~ /$twitterTweetsFolder\/$keyword\/$createdOn\/(.*)\.json/;
		}
		die unless $latestTweetId;
	}
	return $latestTweetId;
}

sub search_tweets {
    my ($keyword, $current, $total, $latestTweetId, $token) = @_;

    my $tweetsUrl;
    if ($token) {
        STDOUT->printflush("\rGetting  [tweets] - [$current / $total] - [$keyword] - token : [$token]                 ");
        $tweetsUrl = "https://api.twitter.com/2/tweets/search/recent?tweet.fields=attachments,author_id,context_annotations,conversation_id," .
                     "created_at,entities,geo,id,in_reply_to_user_id,lang,possibly_sensitive,public_metrics,referenced_tweets,reply_settings," .
                     "source,text,withheld&user.fields=created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url,protected," .
                     "public_metrics,url,username,verified,withheld&max_results=100&expansions=attachments.poll_ids,attachments.media_keys,author_id," .
                     "geo.place_id,in_reply_to_user_id,referenced_tweets.id,entities.mentions.username,referenced_tweets.id.author_id&media." .
                     "fields=duration_ms,height,media_key,preview_image_url,public_metrics," .
                     "type,url,width&pagination_token=$token";
    } else {
        $token = '';

        STDOUT->printflush("\rGetting  [tweets] - [$current / $total] - [$keyword]                                                                    ");
        $tweetsUrl = "https://api.twitter.com/2/tweets/search/recent?tweet.fields=attachments,author_id,context_annotations,conversation_id," .
                     "created_at,entities,geo,id,in_reply_to_user_id,lang,possibly_sensitive,public_metrics,referenced_tweets,reply_settings," .
                     "source,text,withheld&user.fields=created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url,protected," .
                     "public_metrics,url,username,verified,withheld&max_results=100&expansions=attachments.poll_ids,attachments.media_keys,author_id," .
                     "geo.place_id,in_reply_to_user_id,referenced_tweets.id,entities.mentions.username,referenced_tweets.id.author_id&media." .
                     "fields=duration_ms,height,media_key,preview_image_url,public_metrics," .
                     "type,url,width";
    }
    $tweetsUrl .= "&since_id=$latestTweetId" if $latestTweetId;
    $tweetsUrl .= "&query=" . $keyword;
    my $fetched = 0;
    my $content;
    while ($fetched == 0) {
        my $res = $ua->get($tweetsUrl, @headers);
        unless ($res->is_success)
        {
            my $message = $res->message();
            if ($message eq 'Too Many Requests') {
                # say "message : $message";
                p$res;
                say "\nSleeping $sleepSeconds seconds before to try again.";
                for my $sleep (1 .. $sleepSeconds) {
                    STDOUT->printflush("\rSleeping [$sleep / $sleepSeconds]");
                    sleep 1;
                }
                say "";
            } elsif ($message eq 'Bad Request') {
                $content = $res->decoded_content;
                my $json;
                eval {
                    $json = decode_json($content);
                };
                if ($@) {
                    p$res;
                    say "message : $message";
                    say "content : $content";
                    die "failed to get [$tweetsUrl]";
                }
                my $error = shift @{%$json{'errors'}};
                my %error = %$error;
                my $errorMessage = $error{'message'} // die;
                if ($errorMessage =~ /^'since_id' must be a tweet id created after ....-..-..T..:..Z\. Please use a 'since_id' that is larger than .*$/) {
                    return;
                } else {
                    say "errorMessage : $errorMessage";
                    # p%error;
                    die "failed to get [$tweetsUrl]";
                }
            } elsif ($message eq 'Service Unavailable') {
                # say "message : $message";
                say "\nSleeping $sleepSecondsOnFail seconds before to try again.";
                for my $sleep (1 .. $sleepSecondsOnFail) {
                    STDOUT->printflush("\rSleeping [$sleep / $sleepSecondsOnFail]");
                    sleep 1;
                }
                say "";
            } elsif ($message eq 'read timeout') {
                say "\nSleeping 5 seconds before to try again.";
                for my $sleep (1 .. 5) {
                    STDOUT->printflush("\rSleeping [$sleep / 5]");
                    sleep 1;
                }
                say "";
            } else {
                p$res;
                say "message : [$message]";
                die "failed to get [$tweetsUrl]";
            }
        } else {
            $fetched = 1;
            $content = $res->decoded_content;
        }
    }
    my $contentJson;
    eval {
        $contentJson = decode_json($content);
    };
    if ($@) {
        say "Failed to get a proper response from Twitter. Please verify your API configuration file : [$configurationFile]";
        return;
    }

    # Fetching account's followers.
    if (%$contentJson{'data'}) {
        for my $tweetData (@{%$contentJson{'data'}}) {
            my %tweetData = %$tweetData;
            parse_tweet($keyword, %tweetData);
        }

        # Fetching next token if any.
        my $nextToken;
        if (%$contentJson{'meta'}->{'next_token'}) {
            $nextToken = %$contentJson{'meta'}->{'next_token'} // die;
        }
        if ($nextToken) {
            search_tweets($keyword, $current, $total, $latestTweetId, $nextToken);
        }
    }
}

sub parse_tweet {
    my ($keyword, %tweetData) = @_;
    my $createdDatetime = $tweetData{'created_at'} // die;
    my ($date, $hour)   = split 'T', $createdDatetime;
    ($hour)             = split '\.', $hour;
    $createdDatetime    = "$date $hour";
    my $createdOn       = time::datetime_to_timestamp($createdDatetime);
    my $tweetId         = $tweetData{'id'}         // die;
    
    # If the user isn't already known, we initiate its object.
    my $tweetFile = "$twitterTweetsFolder/$keyword/$createdOn/$tweetId.json";
    unless (-f $tweetFile) {
        make_path("$twitterTweetsFolder/$keyword/$createdOn")
            unless (-d "$twitterTweetsFolder/$keyword/$createdOn");

        open my $out, '>:utf8', $tweetFile;
        print $out encode_json\%tweetData;
        close $out;
    }
}