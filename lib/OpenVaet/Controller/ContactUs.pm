package OpenVaet::Controller::ContactUs;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Data::Printer;
use Email::Valid;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;

sub contact_us {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    $self->render(
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub send_contact_us {
    my $self = shift;
    my ($userEmail, $contactText, $currentLanguage);
    my $json = $self->req->json;
    my $ipAddress = $self->remote_addr;
    if ($json) {
        # p$json;
        $userEmail = %$json{'userEmail'};
        $contactText = %$json{'contactText'};
        $currentLanguage = %$json{'currentLanguage'} // 'fr';
    }

    my %response = ();
    if (!$userEmail || !$contactText || !$ipAddress) {
        if ($currentLanguage eq 'en') {
            $response{'status'} = 'Missing email address or contact data';
        } elsif ($currentLanguage eq 'fr') {
            $response{'status'} = 'Addresse courriel ou message manquant';
        } else {
            $self->render(text => 'error');
        }
    } else {
        # Verify if the mail format is valid.
        unless( Email::Valid->address($userEmail) ) {
            if ($currentLanguage eq 'en') {
                $response{'status'} = 'Please verify your email format';
            } elsif ($currentLanguage eq 'fr') {
                $response{'status'} = 'Veuillez vérifier le format de votre addresse courriel';
            } else {
                $self->render(text => 'error');
            }
        } else {

            # Verifies if the email is already known.
            my $sTb = $self->dbh->selectrow_hashref("SELECT id as sessionId FROM session WHERE ipAddress = ?", undef, $ipAddress);
            unless ($sTb) {
                if ($currentLanguage eq 'en') {
                    $response{'status'} = 'Please verify that Javascript is enabled & verify that your browser is up to date';
                } elsif ($currentLanguage eq 'fr') {
                    $response{'status'} = 'Veuillez vérifier que vous avez activé Javascript & que votre navigateur est à jour';
                } else {
                    $self->render(text => 'error');
                }
            } else {
                $response{'status'} = 'ok';
                my $sessionId = %$sTb{'sessionId'} // die;
                my $sth = $self->dbh->prepare("INSERT INTO contact (sessionId, email, text) VALUES (?, ?, ?)");
                $sth->execute($sessionId, $userEmail, $contactText) or die $sth->err();
            }
        }
    }


    $self->render(
        json => \%response
    );
}

1;