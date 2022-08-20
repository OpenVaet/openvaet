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

make_path('gettr_data')
    unless (-d 'gettr_data');

# Postman API V2    : 

# Fetching configuration required (bearer token, targeted profile).
my $gettrUsersFile     = 'gettr_data/gettr_users.json';
my $gettrRelsFile      = 'gettr_data/gettr_users_relations.csv';
my $gettrBansFile      = 'gettr_data/gettr_users_bans.csv';
my $gettrPostsFolder   = 'gettr_data/posts';
my $configurationFile  = 'tasks/gettr/config.cfg';
my %apiConfig          = ();
get_config();
my $gettrProfileName   = $apiConfig{'gettrProfileName'} || die;

# UA used to scrap target.
my $cookie               = HTTP::Cookies->new();
my $ua                   = LWP::UserAgent->new
(
    timeout              => 30,
    cookie_jar           => $cookie,
    agent                => 'Mozilla/5.0 (Windows NT 6.3; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/77.0.3865.90 Safari/537.36'
);
my @headers = (
    'Accept'             => '*/*',
    'Accept-Encoding'    => 'gzip, deflate, br',
    'Connection'         => 'keep-alive'
);

# Initiates values stored.
my %gettrUserRelations   = ();
my %currentUserRelations = ();
my %usersRelationsCount  = ();
my %gettrUsersLookedAt   = ();
my %gettrUsersArchived   = ();
my %gettrUsers           = ();
my $maxUserResults       = 10;        # Defines how many users we will get by query
my $maxPostsResults      = 100;       # Defines how many posts we will get by query
my $sleepSeconds         = 30;        # Defines how long we will sleep on a "Too Many Requests" server reply.
my $delayBetweenUpdates  = 3600 * 1;  # Time we wait (in seconds) between followers updates on a given profile.
my $mainGettrId;

while (1) {

    # Retrieves Gettr users who already have been archived.
    %gettrUsers            = ();
    gettr_user();

    # Retrieves the user data of the configured gettr profile.
    $mainGettrId           = get_gettr_profile();
    %gettrUsersLookedAt    = ();
    $gettrUsersLookedAt{$mainGettrId} = 1; # We will be archiving followers for the main account ; and for relations we wish to cover.

    # Retrieves relations between users which already have been archived.
    %gettrUserRelations    = ();
    %currentUserRelations  = ();
    gettr_user_relation();

    # Retrieves the followers of the configured gettr profile & of the followed / following users.
    get_watched_users_followers_relations();

    # Updates known users data.
    print_user_data();

    # Detecting if users have been "unfollowed" by the watched account(s), or unfollowed the watched account(s)
    # in which case the user was either been banned or volontary unfollowed.
    %gettrUsersArchived    = ();
    verify_gettr_user_existing_relations();

    say "Sleeping [$sleepSeconds] seconds prior to monitor again.";
    sleep $sleepSeconds;
}

sub finalize_banned_users {
    my $gettrUsersBansFile = 'gettr_data/gettr_users_bans_finalized.json';
    my $gettrUsersBansJson = json_from_file($gettrUsersBansFile);
    my @cleanedUsers;
    my $hasChanged = 0;
    my %bannedUsers = ();
    for my $obj (@$gettrUsersBansJson) {
        my %obj = %$obj;
        my $gettrUserName    = $obj{'gettrUserName'};
        my $gettrId          = $obj{'gettrId'};
        my $banSpecificReasons = $obj{'banSpecificReasons'};
        my $localUrl           = $obj{'localUrl'};
        # p%obj;
        # die;
        if ($gettrId) {
            if (exists $bannedUsers{'gettrIds'}->{$gettrId}) {
                die "duplicate gettrId : $gettrId";
            }
        }
        if ($localUrl) {
            die "missing local picture : [$localUrl]" unless -f $localUrl;
        }
        if (exists $bannedUsers{'gettrUserNames'}->{$gettrUserName}) {
            die "duplicate gettrUserName : $gettrUserName";
        }
        $bannedUsers{'gettrIds'}->{$gettrId}                 = 1;
        $bannedUsers{'gettrUserNames'}->{$gettrUserName} = 1;
        unless (exists $obj{'hasMotive'}) {
            my $hasMotive = 0;
            if ($banSpecificReasons) {
                $hasMotive = 1;
            }
            $hasChanged = 1;
            $obj{'hasMotive'} = $hasMotive;

            # Fetching total of archived posts.
            if ($gettrId) {
                say "gettrId: $gettrId";
                my $postsArchived = 0;
                if (-d "$gettrPostsFolder/$gettrId") {
                    say "OK for a direct backup";
                    for my $utsFolder (glob "$gettrPostsFolder/$gettrId/*") {
                        my ($uts) = $utsFolder =~ /\/$gettrId\/(.*)/;
                        next if $uts eq 'update.txt';
                        for my $tweet (glob "$utsFolder/*") {
                            $postsArchived++;
                        }
                    }
                }
                $obj{'postsArchived'} = $postsArchived;
                say "postsArchived: $postsArchived";
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

            # Fetching total of archived posts.
            if ($gettrId) {
                say "gettrId: $gettrId";
                my $postsArchived = 0;
                if (-d "$gettrPostsFolder/$gettrId") {
                    say "OK for a direct backup";
                    for my $utsFolder (glob "$gettrPostsFolder/$gettrId/*") {
                        my ($uts) = $utsFolder =~ /\/$gettrId\/(.*)/;
                        next if $uts eq 'update.txt';
                        for my $tweet (glob "$utsFolder/*") {
                            $postsArchived++;
                        }
                    }
                }
                $obj{'postsArchived'} = $postsArchived;
                say "postsArchived: $postsArchived";
            }
        }
        push @cleanedUsers, \%obj;
    }
    if ($hasChanged) {
        open my $out, '>:utf8', $gettrUsersBansFile;
        print $out encode_json\@cleanedUsers;
        close $out;
    }
    # p$gettrUsersBansJson;
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
 
sub gettr_user {
    my $json = json_from_file($gettrUsersFile);
    %gettrUsers = %$json if $json;
}

sub get_gettr_profile {
    my $gettrProfileUrl = "https://api.gettr.com/s/uinf/$gettrProfileName";
    my $res = $ua->get($gettrProfileUrl, @headers);
    unless ($res->is_success)
    {
        p$res;
        die "failed to get [$gettrProfileUrl]";
    }
    my $content = $res->decoded_content;
    my $contentJson;
    eval {
        $contentJson = decode_json($content);
    };
    if ($@) {
        die "Failed to get a proper response from Gettr. Please verify your API configuration file : [$configurationFile]";
    }
    my %userData = %{%$contentJson{'result'}->{'data'}};
    parse_user(%userData);
}

sub parse_user {
    my (%userData)      = @_;
    my $gettrId         = lc $userData{'_id'}    // die;
    my $gettrName       = $userData{'nickname'};
    my $followersCount  = $userData{'flg'}       // die;
    my $followingCount  = $userData{'flw'}       // die;
    my $gettrUserName   = $userData{'ousername'} // die;
    my $gettrPublicUrl  = "https://gettr.com/$gettrUserName";
    my $description     = $userData{'dsc'};
    my $websiteUrl      = $userData{'website'};
    my $profileImageUrl = $userData{'ico'};
    my $createdOn       = $userData{'cdate'}     // die;
    
    # If the user isn't already known, we initiate its object.
    unless (exists $gettrUsers{$gettrId}) {
        # my %changelog       = ();
        # $changelog{$uts}->{'profileImageUrl'} = $profileImageUrl;
        # $changelog{$uts}->{'followersCount'}  = $followersCount;
        # $changelog{$uts}->{'followingCount'}  = $followingCount;
        # $changelog{$uts}->{'postsCount'}     = $postsCount;
        # $changelog{$uts}->{'gettrName'}     = $gettrName;
        # $changelog{$uts}->{'description'}     = $description;
        # $changelog{$uts}->{'gettrUserName'} = $gettrUserName;
        # $changelog{$uts}->{'createdOn'}       = $createdOn;
        # $changelog{$uts}->{'websiteUrl'}      = $websiteUrl;
        # my $changelog = encode_json\%changelog;
        $gettrUsers{$gettrId}->{'profileImageUrl'} = $profileImageUrl;
        $gettrUsers{$gettrId}->{'followersCount'}  = $followersCount;
        $gettrUsers{$gettrId}->{'followingCount'}  = $followingCount;
        $gettrUsers{$gettrId}->{'gettrName'}       = $gettrName;
        $gettrUsers{$gettrId}->{'description'}     = $description;
        $gettrUsers{$gettrId}->{'gettrUserName'}   = $gettrUserName;
        $gettrUsers{$gettrId}->{'websiteUrl'}      = $websiteUrl;
        # $gettrUsers{$gettrId}->{'changelog'}       = $changelog;
    } else { # Overwise, we verify that if the data which may have changed did.
        # my $changelog = $gettrUsers{$gettrId}->{'changelog'} // die;
        # $changelog    = decode_json($changelog);
        # my %changelog = %$changelog;
        # my $uts       = time::current_timestamp();
        # if ($gettrUsers{$gettrId}->{'postsCount'}     ne $postsCount) {
        #     $changelog{$uts}->{'postsCount'}     = $postsCount;
        # }
        # if ($gettrUsers{$gettrId}->{'followersCount'}  ne $followersCount) {
        #     $changelog{$uts}->{'followersCount'}  = $followersCount;
        # }
        # if ($gettrUsers{$gettrId}->{'followingCount'}  ne $followingCount) {
        #     $changelog{$uts}->{'followingCount'}  = $followingCount;
        # }
        # if ($websiteUrl) {
        #     if (($gettrUsers{$gettrId}->{'websiteUrl'} && ($gettrUsers{$gettrId}->{'websiteUrl'} ne $websiteUrl)) || (!$websiteUrl)) {
        #         $changelog{$uts}->{'websiteUrl'}  = $websiteUrl;
        #     }
        # }
        # if ($gettrUsers{$gettrId}->{'profileImageUrl'} ne $profileImageUrl) {
        #     $changelog{$uts}->{'profileImageUrl'} = $profileImageUrl;
        # }
        # if ($gettrUsers{$gettrId}->{'description'}  ne $description) {
        #     $changelog{$uts}->{'description'}  = $description;
        # }
        # if ($gettrUsers{$gettrId}->{'gettrUserName'}  ne $gettrUserName) {
        #     $changelog{$uts}->{'gettrUserName'}  = $gettrUserName;
        # }
        # $changelog = encode_json\%changelog;
        $gettrUsers{$gettrId}->{'profileImageUrl'} = $profileImageUrl;
        $gettrUsers{$gettrId}->{'followersCount'}  = $followersCount;
        $gettrUsers{$gettrId}->{'followingCount'}  = $followingCount;
        $gettrUsers{$gettrId}->{'gettrName'}       = $gettrName;
        $gettrUsers{$gettrId}->{'description'}     = $description;
        $gettrUsers{$gettrId}->{'gettrUserName'}   = $gettrUserName;
        $gettrUsers{$gettrId}->{'websiteUrl'}      = $websiteUrl;
        # $gettrUsers{$gettrId}->{'changelog'}       = $changelog;
    }
    return $gettrId;
}

sub gettr_user_relation {
    if (-f $gettrRelsFile) {
        open my $in, '<:utf8', $gettrRelsFile;
        while (<$in>) {
            my ($gettrUserRelationType, $gettrUser1Id, $gettrUser2Id) = split ';', $_;
            if ($gettrUserRelationType == 1) {
                $gettrUserRelations{$gettrUser1Id}->{$gettrUser2Id} = 1;
            } else {
                delete $gettrUserRelations{$gettrUser1Id}->{$gettrUser2Id};
            }
        }
        close $in;
    }
}

sub get_watched_users_followers_relations {
    for my $gettrId (sort keys %gettrUsers) {
        next unless exists $gettrUsersLookedAt{$gettrId};
        my $relationsUpdateTimestamp = $gettrUsers{$gettrId}->{'relationsUpdateTimestamp'};
        my $currentTimetamp          = time::current_timestamp;
        my $gettrUserName            = $gettrUsers{$gettrId}->{'gettrUserName'} // die;
        %usersRelationsCount = ();
        get_user_follows('followers', $gettrId, $gettrUserName, 0, $maxUserResults);
        %usersRelationsCount = ();
        get_user_follows('followings', $gettrId, $gettrUserName, 0, $maxUserResults);

        # Updating user update timestamp.
        $gettrUsers{$gettrId}->{'relationsUpdateTimestamp'} = $currentTimetamp;
    }
}

sub get_user_follows {
    my ($dataType, $gettrId, $gettrUserName, $minResult, $maxResult) = @_;
    my $gettrPublicUrl  = "https://gettr.com/user/$gettrUserName";
    # say "Getting  [$dataType] data for [$gettrPublicUrl] - [$minResult / $maxResult]";
    my $relationsUrl    = "https://api.gettr.com/u/user/$gettrProfileName/$dataType/?offset=$minResult&max=$maxResult&incl=userstats|userinfo";
    my $fetched = 0;
    my $content;
    while ($fetched == 0) {
        my $res = $ua->get($relationsUrl, @headers);
        unless ($res->is_success)
        {
            my $message = $res->message();
            if ($message eq 'Too Many Requests') {
                # say "message : $message";
                say "Sleeping $sleepSeconds seconds before to try again.";
                for my $sleep (1 .. $sleepSeconds) {
                    STDOUT->printflush("\rSleeping [$sleep / $sleepSeconds]");
                    sleep 1;
                }
                say "";
            } else {
                p$res;
                say "message : [$message]";
                die "failed to get [$relationsUrl]";
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
        die "Failed to get a proper response from Gettr. Please verify your API configuration file : [$configurationFile]";
    }

    # Fetching account's followers.
    my $currentCount = keys %usersRelationsCount;
    for my $gUId (sort keys %{%$contentJson{'result'}->{'aux'}->{'uinf'}}) {
        my %userData = %{%$contentJson{'result'}->{'aux'}->{'uinf'}->{$gUId}};
        my $relatedGettrUserId = parse_user(%userData);
        $usersRelationsCount{$relatedGettrUserId} = 1;
        if ($dataType eq 'followers') {
            verify_gettr_user_relation($relatedGettrUserId, $gettrId);
        } else {
            verify_gettr_user_relation($gettrId, $relatedGettrUserId);
        }
        # say "relatedGettrUserId : $relatedGettrUserId";
    }
    my $postCount  = keys %usersRelationsCount;
    if ($currentCount != $postCount) {
        $minResult = $minResult + $maxUserResults;
        $maxResult = $maxResult + $maxUserResults;
        get_user_follows($dataType, $gettrId, $gettrUserName, $minResult, $maxResult);
    }
}

sub verify_gettr_user_relation {
    my ($gettrUser1Id, $gettrUser2Id) = @_;
    unless (exists $gettrUserRelations{$gettrUser1Id}->{$gettrUser2Id}) {
        $gettrUserRelations{$gettrUser1Id}->{$gettrUser2Id} = 1;
        open my $out, '>>:utf8', $gettrRelsFile;
        say $out "1;$gettrUser1Id;$gettrUser2Id;";
        close $out;
    }
    $currentUserRelations{$gettrUser1Id}->{$gettrUser2Id} = 1;
}

sub flag_unfollowed_relation {
    my ($gettrUser1Id, $gettrUser2Id) = @_;
    delete $gettrUserRelations{$gettrUser1Id}->{$gettrUser2Id};
    open my $out, '>>:utf8', $gettrRelsFile;
    say $out "2;$gettrUser1Id;$gettrUser2Id;";
    close $out;
}

sub verify_gettr_user_existing_relations {
    for my $gettrUser1Id (sort keys %gettrUserRelations) {
        my $gettrUser1Name = $gettrUsers{$gettrUser1Id}->{'gettrUserName'} // die "gettrUser1Id : $gettrUser1Id";
        for my $gettrUser2Id (sort keys %{$gettrUserRelations{$gettrUser1Id}}) {
            my $gettrUser2Name = $gettrUsers{$gettrUser2Id}->{'gettrUserName'} // die "gettrUser2Id : $gettrUser2Id";
            unless (exists $currentUserRelations{$gettrUser1Id}->{$gettrUser2Id}) {
                my $currentDatetime  = time::current_datetime();
                flag_unfollowed_relation($gettrUser1Id, $gettrUser2Id);
                say "$currentDatetime - [$gettrUser1Name] has unfollowed [$gettrUser2Id] - $gettrUser2Name";
            } else {
                # Indexing users with relations toward a watched account.
                $gettrUsersArchived{$gettrUser1Id} = $gettrUser1Name;
                $gettrUsersArchived{$gettrUser2Id} = $gettrUser2Name;
            }
        }
    }
}

sub print_user_data {
    my $gettrUsers = encode_json\%gettrUsers;
    open my $out, '>:utf8', $gettrUsersFile;
    print $out $gettrUsers;
    close $out;
}