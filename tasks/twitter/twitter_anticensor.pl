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

make_path('twitter_data')
    unless (-d 'twitter_data');

# API limits        : https://developer.twitter.com/en/portal/products
# Twitter tutorials : https://developer.twitter.com/en/docs/tutorials
# Postman API V2    : https://www.postman.com/twitter/workspace/twitter-s-public-workspace/collection/9956214-784efcda-ed4c-4491-a4c0-a26470a67400?ctx=documentation

# Fetching configuration required (bearer token, targeted profile).
my $twitterUsersFile     = 'twitter_data/twitter_users.json';
my $twitterRelsFile      = 'twitter_data/twitter_users_relations.csv';
my $twitterBansFile      = 'twitter_data/twitter_users_bans.csv';
my $twitterTweetsFolder  = 'twitter_data/tweets';
my $twitterUsersBansFile = 'twitter_data/twitter_users_bans_finalized.json';
my $twitterUsersBansJson = json_from_file($twitterUsersBansFile); # Loads users known to have been banned.
my $configurationFile    = 'tasks/twitter/api_config.cfg';
my %apiConfig            = ();
get_config();
my $twitterProfileName   = $apiConfig{'twitterProfileName'} || die;
my $bearerToken          = $apiConfig{'bearerToken'}        || die;

# UA used to scrap target.
my $cookie               = HTTP::Cookies->new();
my $ua                   = LWP::UserAgent->new
(
    timeout              => 30,
    cookie_jar           => $cookie,
    agent                => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
);
my @headers = (
    'Authorization'      => 'Bearer ' . $bearerToken,
    'Accept'             => '*/*',
    'Accept-Encoding'    => 'gzip, deflate, br',
    'Connection'         => 'keep-alive'
);

# Initiates values stored.
my %twitterUsersBans     = ();
my %twitterUserRelations = ();
my %currentUserRelations = ();
my %twitterUsersLookedAt = ();
my %twitterUsersArchived = ();
my %twitterUsers         = ();
my $maxUserResults       = 1000;      # Defines how many users we will get by query
my $maxTweetsResults     = 100;       # Defines how many tweets we will get by query
my $sleepSecondsOnFail   = 10;        # Defines how long we will sleep on a failed query.
my $sleepSeconds         = 900;       # Defines how long we will sleep on a "Too Many Requests" server reply.
my $delayBetweenUpdates  = 3600 * 1;  # Time we wait (in seconds) between followers updates on a given profile.
my $mainTwitterId;

# finalize_banned_users();
# die;

while (1) {

    # Retrieves Twitter users who already have been archived.
    %twitterUsers            = ();
    %twitterUsersBans        = ();
    twitter_user();
    $twitterUsersBansJson    = json_from_file($twitterUsersBansFile); # Loads users known to have been banned.

    # Retrieves the user data of the configured twitter profile.
    $mainTwitterId           = get_twitter_profile();
    %twitterUsersLookedAt    = ();
    $twitterUsersLookedAt{$mainTwitterId} = 1; # We will be archiving followers for the main account ; and for relations we wish to cover.

    # Retrieves relations between users which already have been archived.
    %twitterUserRelations    = ();
    %currentUserRelations    = ();
    twitter_user_relation();

    # Retrieves the followers of the configured twitter profile & of the followed / following users.
    get_watched_users_followers_relations();

    # Detecting if users have been "unfollowed" by the watched account(s), or unfollowed the watched account(s)
    # in which case the user was either been banned or volontary unfollowed.
    %twitterUsersArchived    = ();
    verify_twitter_user_existing_relations();

    # For each account known but which hasn't been verified through relations,
    # or isn't known to be banned, verify the status every 48 hours.
    organize_bans();
    verify_known_users();

    # Updates known users data.
    print_user_data();

    # Listing users of interest & archiving their tweets.
    archive_twitter_users_tweets();

    # Fetching twitter users profile pictures (when available).
    archive_twitter_users_profile_pictures();

    # Verifying every tweet, and checking if medias are requiring to be downloaded.
    # verify_tweets_medias();

    # Updates known users data.
    print_user_data();

    # Fetching twitter banned users, controling data integrity & evaluating archives available.
    finalize_banned_users();

    say "Sleeping [$sleepSeconds] seconds prior to monitor again.";
    sleep $sleepSeconds;
}

sub organize_bans {
    if ($twitterUsersBansJson) {
        for my $uData (@$twitterUsersBansJson) {
            my $twitterUserName = %$uData{'twitterUserName'} // die;
            $twitterUsersBans{$twitterUserName} = 1;
        }
    }
}

sub verify_known_users {
    my ($current, $total) = (0, 0);
    for my $twitterUserId (sort keys %twitterUsers) {
        my $twitterUserName    = $twitterUsers{$twitterUserId}->{'twitterUserName'} // die;
        next if exists $twitterUsersArchived{$twitterUserId};
        next if exists $twitterUsersBans{$twitterUserName};
        my $latestStatusUpdate = $twitterUsers{$twitterUserId}->{'latestStatusUpdate'};
        my $currentUts         = time::current_timestamp();
        if (!$latestStatusUpdate || ($latestStatusUpdate && ($latestStatusUpdate + 86400 < $currentUts))) {
            $total++;
        }
    }
    for my $twitterUserId (sort keys %twitterUsers) {
        my $twitterUserName    = $twitterUsers{$twitterUserId}->{'twitterUserName'} // die;
        next if exists $twitterUsersArchived{$twitterUserId};
        next if exists $twitterUsersBans{$twitterUserName};
        my $latestStatusUpdate = $twitterUsers{$twitterUserId}->{'latestStatusUpdate'};
        my $currentUts         = time::current_timestamp();
        if (!$latestStatusUpdate || ($latestStatusUpdate && ($latestStatusUpdate + 86400 < $currentUts))) {
            $current++;
            STDOUT->printflush("\rRefreshing non related users [$current / $total]");
            my $currentDatetime  = time::current_datetime();
            my $isBanned         = verify_user_ban($twitterUserId, $twitterUserName);
            if ($isBanned == 1) {
                say "\n$currentDatetime - [$twitterUserName] has been suspended.";
                open my $out, '>>:utf8', $twitterBansFile;
                say $out "$currentDatetime;$twitterUserId;$twitterUserName;";
                close $out;
            } else {
                $twitterUsersArchived{$twitterUserId} = $twitterUserName;
            }
            $twitterUsers{$twitterUserId}->{'latestStatusUpdate'} = $currentUts;
        }
    }
    say "" if $total;
}

sub finalize_banned_users {
    my @cleanedUsers;
    my $hasChanged = 0;
    my %bannedUsers = ();
    for my $obj (@$twitterUsersBansJson) {
        my %obj = %$obj;
        my $twitterUserName    = $obj{'twitterUserName'};
        my $twitterId          = $obj{'twitterId'};
        my $banSpecificReasons = $obj{'banSpecificReasons'};
        my $localUrl           = $obj{'localUrl'};
        # p%obj;
        # die;
        if ($twitterId) {
            if (exists $bannedUsers{'twitterIds'}->{$twitterId}) {
                die "duplicate twitterId : $twitterId";
            }
        }
        if ($localUrl) {
            die "missing local picture : [$localUrl]" unless -f $localUrl;
        }
        if (exists $bannedUsers{'twitterUserNames'}->{$twitterUserName}) {
            die "duplicate twitterUserName : $twitterUserName";
        }
        $bannedUsers{'twitterIds'}->{$twitterId}                 = 1;
        $bannedUsers{'twitterUserNames'}->{$twitterUserName} = 1;
        unless (exists $obj{'hasMotive'}) {
            my $hasMotive = 0;
            if ($banSpecificReasons) {
                $hasMotive = 1;
            }
            $hasChanged = 1;
            $obj{'hasMotive'} = $hasMotive;

            # Fetching total of archived tweets.
            if ($twitterId) {
                say "twitterId: $twitterId";
                my $tweetsArchived = 0;
                if (-d "$twitterTweetsFolder/$twitterId") {
                    say "OK for a direct backup";
                    for my $utsFolder (glob "$twitterTweetsFolder/$twitterId/*") {
                        my ($uts) = $utsFolder =~ /\/$twitterId\/(.*)/;
                        next if $uts eq 'update.txt';
                        for my $tweet (glob "$utsFolder/*") {
                            $tweetsArchived++;
                        }
                    }
                }
                $obj{'tweetsArchived'} = $tweetsArchived;
                say "tweetsArchived: $tweetsArchived";
            }
        }
        unless (exists $obj{'hasAltContact'}) {
            my $hasAltContact = 0;
            if (exists $obj{'altContacts'}) {
                for my $contactLabel (sort keys %{$obj{'altContacts'}}) {
                    if ($contactLabel ne 'Internet Wayback Machine') {
                        $hasAltContact = 1;
                    }
                }
            }
            $hasChanged = 1;
            $obj{'hasAltContact'} = $hasAltContact;

            # Fetching total of archived tweets.
            if ($twitterId) {
                say "twitterId: $twitterId";
                my $tweetsArchived = 0;
                if (-d "$twitterTweetsFolder/$twitterId") {
                    say "OK for a direct backup";
                    for my $utsFolder (glob "$twitterTweetsFolder/$twitterId/*") {
                        my ($uts) = $utsFolder =~ /\/$twitterId\/(.*)/;
                        next if $uts eq 'update.txt';
                        for my $tweet (glob "$utsFolder/*") {
                            $tweetsArchived++;
                        }
                    }
                }
                $obj{'tweetsArchived'} = $tweetsArchived;
                say "tweetsArchived: $tweetsArchived";
            }
        }
        push @cleanedUsers, \%obj;
    }
    if ($hasChanged) {
        open my $out, '>:utf8', $twitterUsersBansFile;
        print $out encode_json\@cleanedUsers;
        close $out;
    }
    # p$twitterUsersBansJson;
    # die;
}

sub get_config {
    die "missing file [$configurationFile]" unless -f $configurationFile;
    my $json   = json_from_file($configurationFile);
    %apiConfig = %$json;
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
 
sub twitter_user {
    my $json = json_from_file($twitterUsersFile);
    %twitterUsers = %$json if $json;
}

sub get_twitter_profile {
    my $twitterProfileUrl         = "https://api.twitter.com/2/users/by/username/$twitterProfileName?user.fields=" .
                                    "created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url," .
                                    "protected,public_metrics,url,username,verified,withheld";
    my $res = $ua->get($twitterProfileUrl, @headers);
    unless ($res->is_success)
    {
        p$res;
        die "failed to get [$twitterProfileUrl]";
    }
    my $content = $res->decoded_content;
    my $contentJson;
    eval {
        $contentJson = decode_json($content);
    };
    if ($@) {
        die "Failed to get a proper response from Twitter. Please verify your API configuration file : [$configurationFile]";
    }
    my %userData = %{%$contentJson{'data'}};
    parse_user(%userData);
}

sub parse_user {
    my (%userData)      = @_;
    # p%userData;
    my $twitterId       = $userData{'id'}                                  // die;
    my $twitterName     = $userData{'name'}                                // die;
    my $tweetsCount     = $userData{'public_metrics'}->{'tweet_count'}     // die;
    my $followersCount  = $userData{'public_metrics'}->{'followers_count'} // die;
    my $followingCount  = $userData{'public_metrics'}->{'following_count'} // die;
    my $twitterUserName = $userData{'username'}    // die;
    my $twitterPublicUrl = "https://twitter.com/$twitterUserName";
    # say "Parsing [$twitterPublicUrl]";
    my $description     = $userData{'description'} // die;

    # Reformats description if required.
    my $websiteUrl;
    for my $entityType (sort keys %{$userData{'entities'}}) {
        if ($entityType eq 'description') {
            for my $entityLabel (sort keys %{$userData{'entities'}->{$entityType}}) {
                if ($entityLabel eq 'urls') {
                    for my $urlData (@{$userData{'entities'}->{$entityType}->{$entityLabel}}) {
                        my $url         = %$urlData{'url'}          // die;
                        my $expandedUrl = %$urlData{'expanded_url'} // die;
                        my $displayUrl  = %$urlData{'display_url'}  // die;
                        $description    =~ s/$url/<a href="$expandedUrl" target="_blank">$displayUrl<\/a>/g;
                    }
                } elsif ($entityLabel eq 'hashtags' || $entityLabel eq 'mentions' || $entityLabel eq 'cashtags') {
                    next;
                } else {
                    die "entityLabel : $entityLabel";
                }
            }
        } elsif ($entityType eq 'url') {
            for my $entityLabel (sort keys %{$userData{'entities'}->{$entityType}}) {
                if ($entityLabel eq 'urls') {
                    for my $urlData (@{$userData{'entities'}->{$entityType}->{$entityLabel}}) {
                        my $url = %$urlData{'expanded_url'} // next;
                        $websiteUrl = $url;
                    }
                } elsif ($entityLabel eq 'mentions') {
                    next;
                } else {
                    die "entityLabel : $entityLabel";
                }
            }
        } else {
            die "entityType : $entityType";
        }
    }

    my $profileImageUrl = $userData{'profile_image_url'} // die;
    my $createdDatetime = $userData{'created_at'}        // die;
    
    # If the user isn't already known, we initiate its object.
    unless (exists $twitterUsers{$twitterId}) {
        my ($date, $hour)   = split 'T', $createdDatetime;
        ($hour)             = split '\.', $hour;
        $createdDatetime    = "$date $hour";
        my $createdOn       = time::datetime_to_timestamp($createdDatetime);
        my $uts             = time::current_timestamp();
        # my %changelog       = ();
        # $changelog{$uts}->{'profileImageUrl'} = $profileImageUrl;
        # $changelog{$uts}->{'followersCount'}  = $followersCount;
        # $changelog{$uts}->{'followingCount'}  = $followingCount;
        # $changelog{$uts}->{'tweetsCount'}     = $tweetsCount;
        # $changelog{$uts}->{'twitterName'}     = $twitterName;
        # $changelog{$uts}->{'description'}     = $description;
        # $changelog{$uts}->{'twitterUserName'} = $twitterUserName;
        # $changelog{$uts}->{'createdOn'}       = $createdOn;
        # $changelog{$uts}->{'websiteUrl'}      = $websiteUrl;
        # my $changelog = encode_json\%changelog;
        $twitterUsers{$twitterId}->{'profileImageUrl'} = $profileImageUrl;
        $twitterUsers{$twitterId}->{'followersCount'}  = $followersCount;
        $twitterUsers{$twitterId}->{'followingCount'}  = $followingCount;
        $twitterUsers{$twitterId}->{'tweetsCount'}     = $tweetsCount;
        $twitterUsers{$twitterId}->{'twitterName'}     = $twitterName;
        $twitterUsers{$twitterId}->{'description'}     = $description;
        $twitterUsers{$twitterId}->{'twitterUserName'} = $twitterUserName;
        $twitterUsers{$twitterId}->{'websiteUrl'}      = $websiteUrl;
        # $twitterUsers{$twitterId}->{'changelog'}       = $changelog;
    } else { # Overwise, we verify that if the data which may have changed did.
        # my $changelog = $twitterUsers{$twitterId}->{'changelog'} // die;
        # $changelog    = decode_json($changelog);
        # my %changelog = %$changelog;
        # my $uts       = time::current_timestamp();
        # if ($twitterUsers{$twitterId}->{'tweetsCount'}     ne $tweetsCount) {
        #     $changelog{$uts}->{'tweetsCount'}     = $tweetsCount;
        # }
        # if ($twitterUsers{$twitterId}->{'followersCount'}  ne $followersCount) {
        #     $changelog{$uts}->{'followersCount'}  = $followersCount;
        # }
        # if ($twitterUsers{$twitterId}->{'followingCount'}  ne $followingCount) {
        #     $changelog{$uts}->{'followingCount'}  = $followingCount;
        # }
        # if ($websiteUrl) {
        #     if (($twitterUsers{$twitterId}->{'websiteUrl'} && ($twitterUsers{$twitterId}->{'websiteUrl'} ne $websiteUrl)) || (!$websiteUrl)) {
        #         $changelog{$uts}->{'websiteUrl'}  = $websiteUrl;
        #     }
        # }
        # if ($twitterUsers{$twitterId}->{'profileImageUrl'} ne $profileImageUrl) {
        #     $changelog{$uts}->{'profileImageUrl'} = $profileImageUrl;
        # }
        # if ($twitterUsers{$twitterId}->{'description'}  ne $description) {
        #     $changelog{$uts}->{'description'}  = $description;
        # }
        # if ($twitterUsers{$twitterId}->{'twitterUserName'}  ne $twitterUserName) {
        #     $changelog{$uts}->{'twitterUserName'}  = $twitterUserName;
        # }
        # $changelog = encode_json\%changelog;
        $twitterUsers{$twitterId}->{'profileImageUrl'} = $profileImageUrl;
        $twitterUsers{$twitterId}->{'followersCount'}  = $followersCount;
        $twitterUsers{$twitterId}->{'followingCount'}  = $followingCount;
        $twitterUsers{$twitterId}->{'tweetsCount'}     = $tweetsCount;
        $twitterUsers{$twitterId}->{'twitterName'}     = $twitterName;
        $twitterUsers{$twitterId}->{'description'}     = $description;
        $twitterUsers{$twitterId}->{'twitterUserName'} = $twitterUserName;
        $twitterUsers{$twitterId}->{'websiteUrl'}      = $websiteUrl;
        # $twitterUsers{$twitterId}->{'changelog'}       = $changelog;
    }
    return $twitterId;
}

sub twitter_user_relation {
    if (-f $twitterRelsFile) {
        open my $in, '<:utf8', $twitterRelsFile;
        while (<$in>) {
            my ($twitterUserRelationType, $twitterUser1Id, $twitterUser2Id) = split ';', $_;
            if ($twitterUserRelationType == 1) {
                $twitterUserRelations{$twitterUser1Id}->{$twitterUser2Id} = 1;
            } else {
                delete $twitterUserRelations{$twitterUser1Id}->{$twitterUser2Id};
            }
        }
        close $in;
    }
}

sub get_watched_users_followers_relations {
    for my $twitterId (sort{$a <=> $b} keys %twitterUsers) {
        next unless exists $twitterUsersLookedAt{$twitterId};
        my $relationsUpdateTimestamp = $twitterUsers{$twitterId}->{'relationsUpdateTimestamp'};
        my $currentTimetamp          = time::current_timestamp;
        my $twitterUserName          = $twitterUsers{$twitterId}->{'twitterUserName'} // die;
        get_user_follows('followers', $twitterId, $twitterUserName);
        get_user_follows('following', $twitterId, $twitterUserName);

        # Updating user update timestamp.
        $twitterUsers{$twitterId}->{'relationsUpdateTimestamp'} = $currentTimetamp;
    }
}

sub get_user_follows {
    my ($dataType, $twitterId, $twitterUserName, $token) = @_;
    my $twitterPublicUrl = "https://twitter.com/$twitterUserName";

    my $followersUrl;
    if ($token) {
        say "Getting  [$dataType] data for [$twitterPublicUrl] - token : [$token]";
        $followersUrl = "https://api.twitter.com/2/users/$twitterId/$dataType?max_results=$maxUserResults&pagination_token=$token&user.fields=" .
                         "created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url," .
                         "protected,public_metrics,url,username,verified,withheld";
    } else {
        $token = '';
        say "Getting  [$dataType] data for [$twitterPublicUrl]";
        $followersUrl = "https://api.twitter.com/2/users/$twitterId/$dataType?max_results=$maxUserResults&user.fields=" .
                         "created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url," .
                         "protected,public_metrics,url,username,verified,withheld";
    }
    my $fetched = 0;
    my $content;
    while ($fetched == 0) {
        my $res = $ua->get($followersUrl, @headers);
        unless ($res->is_success)
        {
            my $message = $res->message();
            if ($message eq 'Too Many Requests') {
                # say "message : $message";
                say "\nSleeping $sleepSeconds seconds before to try again.";
                for my $sleep (1 .. $sleepSeconds) {
                    STDOUT->printflush("\rSleeping [$sleep / $sleepSeconds]");
                    sleep 1;
                }
                say "";
            } elsif ($message eq 'Service Unavailable') {
                # say "message : $message";
                say "\nSleeping $sleepSecondsOnFail seconds before to try again.";
                for my $sleep (1 .. $sleepSecondsOnFail) {
                    STDOUT->printflush("\rSleeping [$sleep / $sleepSecondsOnFail]");
                    sleep 1;
                }
                say "";
            } else {
                p$res;
                say "message : [$message]";
                die "failed to get [$followersUrl]";
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
        die "Failed to get a proper response from Twitter. Please verify your API configuration file : [$configurationFile]";
    }

    # Fetching account's followers.
    for my $userData (@{%$contentJson{'data'}}) {
        my %userData = %$userData;
        # p%userData;
        my $relatedTwitterUserId = parse_user(%userData);
        if ($dataType eq 'followers') {
            verify_twitter_user_relation($relatedTwitterUserId, $twitterId);
        } else {
            verify_twitter_user_relation($twitterId, $relatedTwitterUserId);
        }
        # say "relatedTwitterUserId : $relatedTwitterUserId";
    }

    # Fetching next token if any.
    my $nextToken;
    if (%$contentJson{'meta'}->{'next_token'}) {
        $nextToken = %$contentJson{'meta'}->{'next_token'} // die;
    }
    if ($nextToken) {
        get_user_follows($dataType, $twitterId, $twitterUserName, $nextToken);
    }
}

sub verify_twitter_user_relation {
    my ($twitterUser1Id, $twitterUser2Id) = @_;
    unless (exists $twitterUserRelations{$twitterUser1Id}->{$twitterUser2Id}) {
        $twitterUserRelations{$twitterUser1Id}->{$twitterUser2Id} = 1;
        open my $out, '>>:utf8', $twitterRelsFile;
        say $out "1;$twitterUser1Id;$twitterUser2Id;";
        close $out;
    }
    $currentUserRelations{$twitterUser1Id}->{$twitterUser2Id} = 1;
}

sub verify_user_ban {
    my ($twitterId, $twitterUserName) = @_;
    my $twitterProfileUrl         = "https://api.twitter.com/2/users/by/username/$twitterUserName?user.fields=" .
                                    "created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url," .
                                    "protected,public_metrics,url,username,verified,withheld";
    # say "Getting  [$twitterUserName] data";
    my $fetched = 0;
    my $content;
    while ($fetched == 0) {
        my $res = $ua->get($twitterProfileUrl, @headers);
        unless ($res->is_success)
        {
            my $message = $res->message();
            if ($message eq 'Too Many Requests') {
                # say "message : $message";
                say "\nSleeping $sleepSeconds seconds before to try again.";
                for my $sleep (1 .. $sleepSeconds) {
                    STDOUT->printflush("\rSleeping [$sleep / $sleepSeconds]");
                    sleep 1;
                }
                say "";
            } elsif ($message eq 'Service Unavailable') {
                # say "message : $message";
                say "\nSleeping $sleepSecondsOnFail seconds before to try again.";
                for my $sleep (1 .. $sleepSecondsOnFail) {
                    STDOUT->printflush("\rSleeping [$sleep / $sleepSecondsOnFail]");
                    sleep 1;
                }
                say "";
            } else {
                p$res;
                say "message : [$message]";
                die "failed to get [$twitterProfileUrl]";
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
        die "Failed to get a proper response from Twitter. Please verify your API configuration file : [$configurationFile]";
    }
    my $isBanned = 0;
    my %userData = %$contentJson;
    if ($userData{'errors'}) {
        my @errorData = @{$userData{'errors'}};
        my $errorData = shift @errorData;
        my %errorData = %$errorData;
        my $detail    = $errorData{'detail'} // die;
        if ($detail) {
            $isBanned = 1 if $detail =~ /User has been suspended:/;
        }
    }
    return $isBanned;
}

sub flag_unfollowed_relation {
    my ($twitterUser1Id, $twitterUser2Id) = @_;
    delete $twitterUserRelations{$twitterUser1Id}->{$twitterUser2Id};
    open my $out, '>>:utf8', $twitterRelsFile;
    say $out "2;$twitterUser1Id;$twitterUser2Id;";
    close $out;
}

sub verify_twitter_user_existing_relations {
    for my $twitterUser1Id (sort{$a <=> $b} keys %twitterUserRelations) {
        my $twitterUser1Name = $twitterUsers{$twitterUser1Id}->{'twitterUserName'} // next;
        for my $twitterUser2Id (sort{$a <=> $b} keys %{$twitterUserRelations{$twitterUser1Id}}) {
            my $twitterUser2Name = $twitterUsers{$twitterUser2Id}->{'twitterUserName'} // next;
            unless (exists $currentUserRelations{$twitterUser1Id}->{$twitterUser2Id}) {
                my $currentDatetime  = time::current_datetime();
                my $isBanned;
                if ($twitterUser1Id == $mainTwitterId) {
                    $isBanned        = verify_user_ban($twitterUser2Id, $twitterUser2Name);
                    if ($isBanned == 1) {
                        open my $out, '>>:utf8', $twitterBansFile;
                        say $out "$currentDatetime;$twitterUser2Id;$twitterUser2Name;";
                        close $out;
                    }
                } else {
                    $isBanned      = verify_user_ban($twitterUser1Id, $twitterUser1Name);
                    if ($isBanned == 1) {
                        open my $out, '>>:utf8', $twitterBansFile;
                        say $out "$currentDatetime;$twitterUser1Id;$twitterUser1Name;";
                        close $out;
                    }
                }
                flag_unfollowed_relation($twitterUser1Id, $twitterUser2Id);
                say "$currentDatetime - [$twitterUser1Name] has unfollowed [$twitterUser2Id] - $twitterUser2Name - isBanned : [$isBanned]";
            } else {
                # Indexing users with relations toward a watched account.
                $twitterUsersArchived{$twitterUser1Id} = $twitterUser1Name;
                $twitterUsersArchived{$twitterUser2Id} = $twitterUser2Name;
            }
        }
    }
}

sub archive_twitter_users_tweets {
    my %twitterUsersToUpdate = ();
    for my $twitterId (sort{$a <=> $b} keys %twitterUsersArchived) {
        make_path("$twitterTweetsFolder/$twitterId")
            unless (-d "$twitterTweetsFolder/$twitterId");
        my $tweetsUpdateTimestampFile = "$twitterTweetsFolder/$twitterId/update.txt";
        if (-f $tweetsUpdateTimestampFile) {
            my $currentTimetamp = time::current_timestamp();
            my $updateTimestamp;
            open my $in, '<:utf8', $tweetsUpdateTimestampFile;
            while (<$in>) {
                $updateTimestamp = $_;
            }
            close $in;
            if ($updateTimestamp) {
                next if ($updateTimestamp + $delayBetweenUpdates) > $currentTimetamp;
            }
            $twitterUsersToUpdate{$twitterId}->{'updateTimestamp'} = $updateTimestamp;
        }
        my $twitterUserName = $twitterUsersArchived{$twitterId} // die;
        $twitterUsersToUpdate{$twitterId}->{'twitterUserName'} = $twitterUserName;
    }
    my $current = 0;
    my $total   = keys %twitterUsersToUpdate;
    for my $twitterId (sort{$a <=> $b} keys %twitterUsersToUpdate) {
        my $twitterUserName = $twitterUsersToUpdate{$twitterId}->{'twitterUserName'} // die;
        my $updateTimestamp = $twitterUsersToUpdate{$twitterId}->{'updateTimestamp'};
        my $latestTweetId;
        if ($updateTimestamp) {

            # Sorting known updates by timestamps.
            my %timestamps = ();
            for my $utsFolder (glob "$twitterTweetsFolder/$twitterId/*") {
                my ($uts) = $utsFolder =~ /\/$twitterId\/(.*)/;
                next if $uts eq 'update.txt';
                $timestamps{$uts} = 1;
            }

            # Fetching latest timestamp's tweet, and extracting its datetime.
            for my $uts (sort{$b <=> $a} keys %timestamps) {
                my $dir = "$twitterTweetsFolder/$twitterId/$uts";
                for my $tweet (glob "$dir/*") {
                    open my $in, '<:utf8', $tweet;
                    my $json;
                    while (<$in>) {
                        $json .= $_;
                    }
                    close $in;
                    $json = decode_json($json);
                    $latestTweetId = %$json{'id'} // die;
                    last;
                }
                last;
            }
        }

        $current++;
        get_user_tweets($twitterId, $twitterUserName, $current, $total, $latestTweetId);
        my $tweetsUpdateTimestampFile = "$twitterTweetsFolder/$twitterId/update.txt";

        log_user_update($tweetsUpdateTimestampFile);
    }
    say "" if $total;
}

sub get_user_tweets {
    my ($twitterId, $twitterUserName, $current, $total, $latestTweetId, $token) = @_;
    my $twitterPublicUrl = "https://twitter.com/$twitterUserName";

    my $tweetsUrl;
    if ($token) {
        STDOUT->printflush("\rGetting  [tweets] - [$current / $total] - [$twitterPublicUrl] - token : [$token]                 ");
        $tweetsUrl = "https://api.twitter.com/2/tweets/search/recent?tweet.fields=attachments,author_id,context_annotations,conversation_id," .
                     "created_at,entities,geo,id,in_reply_to_user_id,lang,possibly_sensitive,public_metrics,referenced_tweets,reply_settings," .
                     "source,text,withheld&user.fields=created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url,protected," .
                     "public_metrics,url,username,verified,withheld&max_results=100&expansions=attachments.poll_ids,attachments.media_keys,author_id," .
                     "geo.place_id,in_reply_to_user_id,referenced_tweets.id,entities.mentions.username,referenced_tweets.id.author_id&media." .
                     "fields=duration_ms,height,media_key,preview_image_url,public_metrics," .
                     "type,url,width&pagination_token=$token";
    } else {
        $token = '';

        STDOUT->printflush("\rGetting  [tweets] - [$current / $total] - [$twitterPublicUrl]                                                                    ");
        $tweetsUrl = "https://api.twitter.com/2/tweets/search/recent?tweet.fields=attachments,author_id,context_annotations,conversation_id," .
                     "created_at,entities,geo,id,in_reply_to_user_id,lang,possibly_sensitive,public_metrics,referenced_tweets,reply_settings," .
                     "source,text,withheld&user.fields=created_at,description,entities,id,location,name,pinned_tweet_id,profile_image_url,protected," .
                     "public_metrics,url,username,verified,withheld&max_results=100&expansions=attachments.poll_ids,attachments.media_keys,author_id," .
                     "geo.place_id,in_reply_to_user_id,referenced_tweets.id,entities.mentions.username,referenced_tweets.id.author_id&media." .
                     "fields=duration_ms,height,media_key,preview_image_url,public_metrics," .
                     "type,url,width";
    }
    $tweetsUrl .= "&since_id=$latestTweetId" if $latestTweetId;
    $tweetsUrl .= "&query=from:" . $twitterUserName;
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
                    # ($latestTweetId) = $errorMessage =~ /^'since_id' must be a tweet id created after ....-..-..T..:..Z\. Please use a 'since_id' that is larger than (.*)$/;
                    # say "\nAdjusting latestTweetId : $latestTweetId";
                    # get_user_tweets($twitterId, $twitterUserName, $current, $total, $latestTweetId);
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
            parse_tweet($twitterId, %tweetData);
        }

        # Fetching next token if any.
        my $nextToken;
        if (%$contentJson{'meta'}->{'next_token'}) {
            $nextToken = %$contentJson{'meta'}->{'next_token'} // die;
        }
        if ($nextToken) {
            get_user_tweets($twitterId, $twitterUserName, $current, $total, $latestTweetId, $nextToken);
        }
    }
}

sub parse_tweet {
    my ($twitterId, %tweetData) = @_;
    my $createdDatetime = $tweetData{'created_at'} // die;
    my ($date, $hour)   = split 'T', $createdDatetime;
    ($hour)             = split '\.', $hour;
    $createdDatetime    = "$date $hour";
    my $createdOn       = time::datetime_to_timestamp($createdDatetime);
    my $tweetId         = $tweetData{'id'}         // die;
    
    # If the user isn't already known, we initiate its object.
    my $tweetFile = "$twitterTweetsFolder/$twitterId/$createdOn/$tweetId.json";
    unless (-f $tweetFile) {
        make_path("$twitterTweetsFolder/$twitterId/$createdOn")
            unless (-d "$twitterTweetsFolder/$twitterId/$createdOn");

        open my $out, '>:utf8', $tweetFile;
        print $out encode_json\%tweetData;
        close $out;
    }
}

sub log_user_update {
    my ($tweetsUpdateTimestampFile) = @_;
    open my $out, '>:utf8', $tweetsUpdateTimestampFile;
    print $out time::current_timestamp();
    close $out;
}

sub archive_twitter_users_profile_pictures {
    make_path("public/twitter_data/profile_images/thumbmails")
        unless (-d "public/twitter_data/profile_images/thumbmails");
    my ($current, $total) = (0, 0);
    for my $twitterId (sort{$a <=> $b} keys %twitterUsers) {
        my $profileImageUrl = $twitterUsers{$twitterId}->{'profileImageUrl'} // die;
        my @parts     = split '\.', $profileImageUrl;
        my $localUrl  = "public/twitter_data/profile_images/thumbmails/$twitterId." . $parts[scalar @parts - 1];
        unless (-f $localUrl) {
            $total++;
        }
        $twitterUsers{$twitterId}->{'localUrl'} = $localUrl;
    }
    for my $twitterId (sort{$a <=> $b} keys %twitterUsers) {
        my $profileImageUrl = $twitterUsers{$twitterId}->{'profileImageUrl'} // die;
        my $localUrl        = $twitterUsers{$twitterId}->{'localUrl'}        // die;
        unless (-f $localUrl) {
            $current++;
            STDOUT->printflush("\rGetting  [users profile pictures] - [$current / $total]   ");
            my $rc = getstore($profileImageUrl, $localUrl);
            if (is_error($rc)) {
                die "getstore of <$profileImageUrl> failed with $rc";
            }
        }
    }
    say "" if $total;
}

sub verify_tweets_medias {
    my ($current, $total, $cpt) = (0, 0, 0);
    my %tweetsByUts = ();
    STDOUT->printflush("\rListing  [tweets indexed]   ");
    for my $twitterId (sort{$a <=> $b} keys %twitterUsers) {
        my $hasActiveRelation  = 0;
        if (
            exists $twitterUserRelations{$twitterId}->{$mainTwitterId} ||
            exists $twitterUserRelations{$mainTwitterId}->{$twitterId} ||
            $twitterId == $mainTwitterId
        ) {
            $hasActiveRelation = 1;
        }
        for my $utsFile (glob "$twitterTweetsFolder/$twitterId/*") {
            next unless -d $utsFile;
            my ($uts) = $utsFile =~ /twitter_data\/tweets\/$twitterId\/(.*)/;
            for my $tweetFile (glob "$utsFile/*\.json") {
                my ($tweetId) = $tweetFile =~ /$utsFile\/(.*)\.json/;
                # unless (-d "public/twitter_data/tweets_images/$twitterId") {
                    $tweetsByUts{$twitterId}->{$uts}->{$tweetId}->{'tweetFile'} = $tweetFile;
                    $tweetsByUts{$twitterId}->{$uts}->{$tweetId}->{'twitterId'} = $twitterId;
                    $cpt++;
                    $total++;
                    if ($cpt == 100) {
                        $cpt = 0;
                        STDOUT->printflush("\rListing  [tweets indexed] - [$total]   ");
                    }
                # }
            }
        }
        $twitterUsers{$twitterId}->{'hasActiveRelation'} = $hasActiveRelation;

        # Comment this line if you want to keep the changelogs.
        delete $twitterUsers{$twitterId}->{'changelog'} if exists $twitterUsers{$twitterId}->{'changelog'};
    }
    for my $twitterId (sort{$a <=> $b} keys %tweetsByUts) {
        # say "twitterId : $twitterId";
        $twitterUsers{$twitterId}->{'indexedTweets'} = ();
        for my $uts (sort{$a <=> $b} keys %{$tweetsByUts{$twitterId}}) {
            for my $tweetId (sort{$a <=> $b} keys %{$tweetsByUts{$twitterId}->{$uts}}) {
                my $tweetFile = "twitter_data/tweets/$twitterId/$uts/$tweetId.json";
                $current++;
                STDOUT->printflush("\rGetting  [tweets indexed] - [$current / $total]   ");
                my $json = json_from_file($tweetFile);
                my $authorId = %$json{'author_id'} // die;
                if ($authorId eq $twitterId) {
                    $twitterUsers{$twitterId}->{'indexedTweets'}->{'ownTweets'}++;
                } else {
                    $twitterUsers{$twitterId}->{'indexedTweets'}->{'reTweets'}++;
                }
                $twitterUsers{$twitterId}->{'indexedTweets'}->{'totalTweets'}++;
                # p$json;
                # die;
                # last if $current > 5;
            }
            $twitterUsers{$twitterId}->{'indexedTweets'}->{'latestTweetUts'} = $uts;
            # last if $current > 5;
        }
        # die;
    }
    say "" if $total;
}

sub print_user_data {
    my $twitterUsers = encode_json\%twitterUsers;
    open my $out, '>:utf8', $twitterUsersFile;
    print $out $twitterUsers;
    close $out;
}