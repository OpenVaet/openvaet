package OpenVaet::Controller::SocialNetworks;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub social_networks {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
	my $summaryFile     = 'social_networks_data/summary.json'; 
	my %summaryStats    = ();
	if (-f $summaryFile) {
		my $json = json_from_file($summaryFile);
		%summaryStats = %$json;
	}
	p%summaryStats;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        summaryStats => \%summaryStats
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

sub keywords_sets {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    # Loads social networks keywords & common keywords.
    my %keywordsSets = ();
    my $tb = $self->dbh->selectall_hashref("SELECT id as keywordsSetId, name as keywordsSetName, userId, keywords FROM rs_keywords_set", 'keywordsSetId');
    for my $keywordsSetId (sort{$a <=> $b} keys %$tb) {
        my $keywordsSetName = %$tb{$keywordsSetId}->{'keywordsSetName'} // die;
        my $userId = %$tb{$keywordsSetId}->{'userId'} // die;
        my $keywords = %$tb{$keywordsSetId}->{'keywords'};
        my $totalKeywords = 0;
        if ($keywords) {
            my @keywords = split '<br \/>', $keywords;
            $totalKeywords = scalar @keywords;
        }
        if ($userId eq $sessionUserId) {
            $keywordsSets{'owned'}->{$keywordsSetName}->{'keywordsSetId'} = $keywordsSetId;
            $keywordsSets{'owned'}->{$keywordsSetName}->{'totalKeywords'} = $totalKeywords;
        } else {
            $keywordsSets{'notOwned'}->{$keywordsSetName}->{'keywordsSetId'} = $keywordsSetId;
            $keywordsSets{'notOwned'}->{$keywordsSetName}->{'totalKeywords'} = $totalKeywords;
        }
    }

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages,
        keywordsSets => \%keywordsSets
    );
}

sub new_keywords_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub save_keywords_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $keywordsSetName = $self->param('keywordsSetName') // die;

    my $userId = $self->session("userId") // die;

    my %json = ();
    $json{'status'} = 'ok';
    $json{'message'} = '';

    # Verify if the name already exists.
    my $tb = $self->dbh->selectrow_hashref("SELECT id FROM rs_keywords_set WHERE name = ?", undef, $keywordsSetName);
    if (keys %$tb) {
        $json{'status'} = 'ko';
        if ($currentLanguage eq 'fr') {
            $json{'message'} = 'Ce set de keywordes existe déjà';
        } else {
            $json{'message'} = 'This set of keywords already exists';
        }
    } else {

        # If the name doesn't exist, proceeding with creation.
        my $sth = $self->dbh->prepare("INSERT INTO rs_keywords_set (name, userId) VALUES (?, $userId)");
        $sth->execute($keywordsSetName) or die $sth->err();
    }

    $self->render(
        json => \%json
    );
}

sub edit_keywords_set {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'fr';
    my $keywordsSetId   = $self->param('keywordsSetId')   // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    my $sessionUserId = $self->session("userId") // die;

    # Loads user keywords & common keywords.
    my $tb = $self->dbh->selectrow_hashref("SELECT name as keywordsSetName, userId, keywords FROM rs_keywords_set WHERE id = $keywordsSetId", undef) or die;
    my $keywordsSetName = %$tb{'keywordsSetName'} // die;
    my $userId = %$tb{'userId'} // die;
    my $keywords = %$tb{'keywords'};
    my $canEdit = 0;
    if ($userId eq $sessionUserId) {
        $canEdit = 1;
    }

    $self->render(
        currentLanguage => $currentLanguage,
        keywordsSetId => $keywordsSetId,
        keywordsSetName => $keywordsSetName,
        canEdit => $canEdit,
        languages => \%languages,
        keywords => $keywords
    );
}

sub save_keywords {
    my $self = shift;
    my $keywords = $self->param("keywords");
    $keywords    =~ s/\"//;
    $keywords    =~ s/\"$//;
    my $keywordsSetId   = $self->param('keywordsSetId')   // die;
    my $sth = $self->dbh->prepare("UPDATE rs_keywords_set SET keywords = ? WHERE id = $keywordsSetId");
    $sth->execute($keywords) or die $sth->err();
    $self->render(
        text => 'ok'
    );
}

sub review_network_posts {
    my $self = shift;

    my $network         = $self->param('network')         // die;
    my $currentLanguage = $self->param('currentLanguage') // die;
	my $forwardedFile;
	if ($network eq 'Twitter') {
		$forwardedFile   = 'social_networks_data/twitter_tweets_forwarded.json';
	} else {
		die "network : $network";
	}

	# Loading keywords.
	my %keywords = ();
    my $sTb = $self->dbh->selectall_hashref("SELECT id as rsKeywordsSetId, keywords FROM rs_keywords_set", 'rsKeywordsSetId');
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

	# Loading texts already transfered.
	my @forwardedPosts = ();
	die unless (-f $forwardedFile);
	my $json = json_from_file($forwardedFile);
	@forwardedPosts = @$json;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        network => $network,
        currentLanguage => $currentLanguage,
        languages => \%languages,
        forwardedPosts => \@forwardedPosts
    );
}

sub finalize_network_review {
    my $self = shift;

    my $network = $self->param('network')         // die;
    my $posts   = $self->param('posts')           // die;
	$posts      = decode_json($posts);
	my %posts   = %$posts;
	my $forwardedFile;
	if ($network eq 'Twitter') {
		$forwardedFile   = 'social_networks_data/twitter_tweets_forwarded.json';
	} else {
		die "network : $network";
	}
	my $summaryFile = 'social_networks_data/summary.json'; 

	# Loading texts already transfered.
	my %summaryStats    = ();
	die unless (-f $summaryFile);
	my $json2 = json_from_file($summaryFile);
	%summaryStats = %$json2;

	# Loading texts already transfered.
	my @forwardedPosts = ();
	die unless (-f $forwardedFile);
	my $json = json_from_file($forwardedFile);
	@forwardedPosts = @$json;
	my @forwardedPostsOut;
    for my $fileData (@forwardedPosts) {
    	my %o = %$fileData;
        my $id = %$fileData{'id'} // die;
        my $review = %$fileData{'review'} // die;
        if ($review == 0) {
        	if (exists $posts{$id}) {
	        	$o{'review'} = 1;
	        	if ($posts{$id}) {
	        		$o{'forward'} = 1;
	        	}
        	}
        }
        push @forwardedPostsOut, \%o;
    }
    $summaryStats{$network}->{'toReview'} = 0;

	open my $out1, '>:utf8', $forwardedFile or die $!;
	print $out1 encode_json\@forwardedPostsOut;
	close $out1;

	open my $out2, '>:utf8', $summaryFile or die $!;
	print $out2 encode_json\%summaryStats;
	close $out2;

    $self->render(
		text => 'ok'
    );
}

1;