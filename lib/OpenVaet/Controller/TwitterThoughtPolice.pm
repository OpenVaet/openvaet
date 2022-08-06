package OpenVaet::Controller::TwitterThoughtPolice;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Math::Round qw(nearest);
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub twitter_thought_police {
	my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my %config          = %{$self->config()};
    my $environment     = $config{'environment'} // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        environment => $environment,
        languages => \%languages
    );
}

sub twitter_followed_users {
    my $self = shift;

    my $currentLanguage    = $self->param('currentLanguage')    // die;
    my $sortCriterion      = $self->param('sortCriterion')      // die;
    my $sortCriterionOrder = $self->param('sortCriterionOrder') // die;
    # say "sortCriterion      : $sortCriterion";
    # say "sortCriterionOrder : $sortCriterionOrder";

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Fetching twitter users & metrics.
    my $twitterUsersFile     = 'twitter_data/twitter_users.json';
    my $twitterUsersJson     = json_from_file($twitterUsersFile);

    my %twitterUsers = ();
    for my $twitterId (sort{$a <=> $b} keys %$twitterUsersJson) {
        my %obj = %{%$twitterUsersJson{$twitterId}};
        next unless $obj{'hasActiveRelation'} == 1;
        $obj{'twitterId'} = $twitterId;
        delete $obj{'changelog'};
        if ($sortCriterion eq 'followers') {
            my $followersCount = $obj{'followersCount'} // die;
            push @{$twitterUsers{$followersCount}}, \%obj;
        } elsif ($sortCriterion eq 'following') {
            my $followingCount = $obj{'followingCount'} // die;
            push @{$twitterUsers{$followingCount}}, \%obj;
        } elsif ($sortCriterion eq 'indexed-tweets') {
            my $totalTweets = $obj{'indexedTweets'}->{'totalTweets'} // 0;
            push @{$twitterUsers{$totalTweets}}, \%obj;
        } elsif ($sortCriterion eq 'tweets') {
            my $tweetsCount = $obj{'tweetsCount'} // die;
            push @{$twitterUsers{$tweetsCount}}, \%obj;
        } elsif ($sortCriterion eq 'users') {
            my $twitterUserName = $obj{'twitterUserName'} // die;
            push @{$twitterUsers{$twitterUserName}}, \%obj;
        }
        # p%obj;
        # last;
    }

    # p$twitterUsersJson;

    $self->render(
        currentLanguage    => $currentLanguage,
        sortCriterion      => $sortCriterion,
        sortCriterionOrder => $sortCriterionOrder,
        languages          => \%languages,
        twitterUsers       => \%twitterUsers
    );
}

sub twitter_banned_users {
    my $self = shift;

    my $currentLanguage    = $self->param('currentLanguage')    // die;
    my $sortCriterion      = $self->param('sortCriterion')      // die;
    my $sortCriterionOrder = $self->param('sortCriterionOrder') // die;
    # say "sortCriterion      : $sortCriterion";
    # say "sortCriterionOrder : $sortCriterionOrder";

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Fetching twitter users & metrics.
    my $twitterUsersBansFile = 'twitter_data/twitter_users_bans_finalized.json';
    my $twitterUsersBansJson = json_from_file($twitterUsersBansFile);
    # p$twitterUsersBansJson;

    my %twitterUsers = ();
    for my $userObj (@$twitterUsersBansJson) {
        my %obj = %$userObj;
        my $banSpecificReasons = $obj{'banSpecificReasons'} // die;
        # p%obj;
        if ($sortCriterion eq 'banned-users') {
            my $twitterUserName = $obj{'twitterUserName'} // die;
            push @{$twitterUsers{$twitterUserName}}, \%obj;
        } elsif ($sortCriterion eq 'banned-date') {
            my $banDate = $obj{'banDate'} // die;
            my $banUts  = time::datetime_to_timestamp($banDate);
            push @{$twitterUsers{$banUts}}, \%obj;
        } elsif ($sortCriterion eq 'banned-indexed-tweets') {
            my $totalTweets = $obj{'tweetsArchived'} // 0;
            push @{$twitterUsers{$totalTweets}}, \%obj;
        } elsif ($sortCriterion eq 'banned-motive') {
            my $hasMotive = $obj{'hasMotive'} // die;
            push @{$twitterUsers{$hasMotive}}, \%obj;
        } elsif ($sortCriterion eq 'banned-followers') {
            my $followersCount = $obj{'followersCount'} // die;
            push @{$twitterUsers{$followersCount}}, \%obj;
        } elsif ($sortCriterion eq 'banned-contact-known') {
            my $hasAltContact = $obj{'hasAltContact'} // die;
            push @{$twitterUsers{$hasAltContact}}, \%obj;
        } else {
            die "sortCriterion : $sortCriterion"
        }
        # p%obj;
        # last;
    }

    # p%twitterUsers;

    # p$twitterUsersBansJson;

    $self->render(
        currentLanguage    => $currentLanguage,
        sortCriterion      => $sortCriterion,
        sortCriterionOrder => $sortCriterionOrder,
        languages          => \%languages,
        twitterUsers       => \%twitterUsers
    );
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

sub open_user_tweets {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // die;
    my $twitterId       = $self->param('twitterId');
    my $twitterUserName     = lc $self->param('twitterUserName')  // die;

    say "twitterId       : $twitterId";
    say "twitterUserName     : $twitterUserName";
    say "currentLanguage : $currentLanguage";

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Fetching twitter user data & metrics.
    my %twitterUser = ();
    my $twitterUsersBansFile = 'twitter_data/twitter_users_bans_finalized.json';
    my $twitterUsersBansJson = json_from_file($twitterUsersBansFile);
    for my $userObj (@$twitterUsersBansJson) {
        my %obj = %$userObj;
        # p%obj;
        my $tName = lc $obj{'twitterUserName'} || die;
        if ($tName eq $twitterUserName) {
            if ($obj{'localUrl'}) {
                $obj{'localUrl'} =~ s/public//;
            }
            if ($obj{'description'}) {
                $obj{'description'} =~ s/\n/<br>/;
            }
            %twitterUser = %obj;
            last;
        }
    }
    die unless keys %twitterUser;
    # p%twitterUser;

    # Parsing tweets.
    my $twitterTweetsFolder  = 'twitter_data/tweets';
    my %tweets = ();
    if ($twitterId) {
        for my $utsFile (glob "$twitterTweetsFolder/$twitterId/*") {
            next unless -d $utsFile;
            my ($uts) = $utsFile =~ /twitter_data\/tweets\/$twitterId\/(.*)/;
            for my $tweetFile (glob "$utsFile/*\.json") {
                my ($tweetId)      = $tweetFile =~ /$utsFile\/(.*)\.json/;
                my $json           = json_from_file($tweetFile);
                my $conversationId = %$json{'conversation_id'} // die;
                $tweets{$conversationId}->{$uts}->{$tweetId}->{'json'} = $json;
            }
        }
    }

    $self->render(
        currentLanguage => $currentLanguage,
        twitterId       => $twitterId,
        languages       => \%languages,
        twitterUser     => \%twitterUser,
        tweets          => \%tweets,
    );
}

1;