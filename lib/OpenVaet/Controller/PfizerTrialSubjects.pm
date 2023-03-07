package OpenVaet::Controller::PfizerTrialSubjects;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::Log;
use JSON;
use Scalar::Util qw(looks_like_number);
use Data::Printer;
use FindBin;
use lib "$FindBin::Bin/../lib";
use session;
use data_formatting;
no autovivification;

sub pregnancies_related {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Loading pregnancies json.
    my $pregnanciesJson;
    open my $in, '<:utf8', 'public/doc/pfizer_trials/pregnancies_report.json';
    while (<$in>) {
        $pregnanciesJson .= $_;
    }
    close $in;
    $pregnanciesJson = decode_json($pregnanciesJson);
    my %pregnanciesJson = %$pregnanciesJson;

    $self->render(
        pregnanciesJson => \%pregnanciesJson,
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub pregnancies_related_subject {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my $subjectId = $self->param('subjectId') // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Loading pregnancies json.
    my $pregnanciesJson;
    open my $in, '<:utf8', 'public/doc/pfizer_trials/pregnancies_report.json';
    while (<$in>) {
        $pregnanciesJson .= $_;
    }
    close $in;
    $pregnanciesJson = decode_json($pregnanciesJson);
    my %pregnanciesJson = %$pregnanciesJson;
    %pregnanciesJson = %{$pregnanciesJson{$subjectId}};
    delete $pregnanciesJson{'pdf'};
    # p%pregnanciesJson;
    $self->render(
        pregnanciesJson => \%pregnanciesJson,
        currentLanguage => $currentLanguage,
        subjectId => $subjectId,
        languages => \%languages
    );

}

sub pregnancies_related_subject_pdf {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my $subjectId = $self->param('subjectId') // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Loading pregnancies json.
    my $pregnanciesJson;
    open my $in, '<:utf8', 'public/doc/pfizer_trials/pregnancies_report.json';
    while (<$in>) {
        $pregnanciesJson .= $_;
    }
    close $in;
    $pregnanciesJson = decode_json($pregnanciesJson);
    my %pregnanciesJson = %$pregnanciesJson;
    %pregnanciesJson = %{$pregnanciesJson{$subjectId}};
    delete $pregnanciesJson{'xpt'};
    p%pregnanciesJson;
    $self->render(
        pregnanciesJson => \%pregnanciesJson,
        currentLanguage => $currentLanguage,
        subjectId => $subjectId,
        languages => \%languages
    );
}

sub pregnancies_related_subject_pdf_page {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my $subjectId       = $self->param('subjectId') // die;
    my $fileNum         = $self->param('fileNum') // die;
    my $fileMd5         = $self->param('fileMd5') // die;
    my $pdfFile         = $self->param('pdfFile') // die;
    my $pageNum         = $self->param('pageNum') // die;
    my $htmlFileLocal   = "public/pfizer_documents/pdf_to_html_files/$fileMd5/page$pageNum.html";

    # Loading pregnancies json.
    my $pregnanciesJson;
    open my $in, '<:utf8', 'public/doc/pfizer_trials/pregnancies_report.json';
    while (<$in>) {
        $pregnanciesJson .= $_;
    }
    close $in;
    $pregnanciesJson = decode_json($pregnanciesJson);
    my %pregnanciesJson = %$pregnanciesJson;
    %pregnanciesJson = %{$pregnanciesJson{$subjectId}};
    delete $pregnanciesJson{'xpt'};
    say "pdfFile : $pdfFile";
    # next;
    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';
    open my $in2, '<:utf8', $htmlFileLocal;
    my $content;
    while (<$in2>) {
        $content .= $_;
    }
    close $in2;
    $content =~ s/src="page$pageNum\.png"/src="\/pfizer_documents\/pdf_to_html_files\/$fileMd5\/page$pageNum\.png"/;
    $content =~ s/$subjectId/<span style="background:yellow">$subjectId<\/span>/;
    my $pdfFileName = "pfizer_documents/native_files/$pdfFile";
    my $totalPages     = keys %{$pregnanciesJson{'pdf'}->{$pdfFile}->{'pages'}};
    die unless $totalPages;
    my $p = 0;
    my $fN = 0;
    my ($formerPageNum, $nextPageNum, $currentPNum);
    for my $pN (sort{$a <=> $b} keys %{$pregnanciesJson{'pdf'}->{$pdfFile}->{'pages'}}) {
        $p++;
        if ($pN == $pageNum) {
            $formerPageNum  = $fN;
            $currentPNum = $p;
        } else {
            if ($currentPNum) {
                $nextPageNum   = $pN;
                last;
            }
        }
        $fN = $pN;
    }
    $self->render(
        pregnanciesJson => \%pregnanciesJson,
        currentLanguage => $currentLanguage,
        pdfFileName     => $pdfFileName,
        subjectId       => $subjectId,
        content         => $content,
        fileNum         => $fileNum,
        fileMd5         => $fileMd5,
        pdfFile         => $pdfFile,
        pageNum         => $pageNum,
        currentPNum     => $currentPNum,
        totalPages      => $totalPages,
        formerPageNum   => $formerPageNum,
        nextPageNum     => $nextPageNum,
        languages       => \%languages
    );
}

sub conflicts_related {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'en';

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Loading conflicts json.
    my $conflictsJson;
    open my $in, '<:utf8', 'public/doc/pfizer_trials/josh_to_local_report.json';
    while (<$in>) {
        $conflictsJson .= $_;
    }
    close $in;
    $conflictsJson = decode_json($conflictsJson);
    my %conflictsJson = %$conflictsJson;

    $self->render(
        conflictsJson => \%conflictsJson,
        currentLanguage => $currentLanguage,
        languages => \%languages
    );
}

sub conflicts_related_subject {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my $subjectId = $self->param('subjectId') // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Loading conflicts json.
    my $conflictsJson;
    open my $in, '<:utf8', 'public/doc/pfizer_trials/josh_to_local_report.json';
    while (<$in>) {
        $conflictsJson .= $_;
    }
    close $in;
    $conflictsJson = decode_json($conflictsJson);
    my %conflictsJson = %$conflictsJson;
    %conflictsJson = %{$conflictsJson{$subjectId}};
    delete $conflictsJson{'pdf'};
    # p%conflictsJson;
    $self->render(
        conflictsJson => \%conflictsJson,
        currentLanguage => $currentLanguage,
        subjectId => $subjectId,
        languages => \%languages
    );

}

sub conflicts_related_subject_pdf {
    my $self = shift;

    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my $subjectId = $self->param('subjectId') // die;

    # Loggin session if unknown.
    session::session_from_self($self);

    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';

    # Loading conflicts json.
    my $conflictsJson;
    open my $in, '<:utf8', 'public/doc/pfizer_trials/josh_to_local_report.json';
    while (<$in>) {
        $conflictsJson .= $_;
    }
    close $in;
    $conflictsJson = decode_json($conflictsJson);
    my %conflictsJson = %$conflictsJson;
    %conflictsJson = %{$conflictsJson{$subjectId}};
    delete $conflictsJson{'xpt'};
    p%conflictsJson;
    $self->render(
        conflictsJson => \%conflictsJson,
        currentLanguage => $currentLanguage,
        subjectId => $subjectId,
        languages => \%languages
    );
}

sub conflicts_related_subject_pdf_page {
    my $self = shift;
    my $currentLanguage = $self->param('currentLanguage') // 'en';
    my $subjectId       = $self->param('subjectId') // die;
    my $fileNum         = $self->param('fileNum') // die;
    my $fileMd5         = $self->param('fileMd5') // die;
    my $pdfFile         = $self->param('pdfFile') // die;
    my $pageNum         = $self->param('pageNum') // die;
    my $htmlFileLocal   = "public/pfizer_documents/pdf_to_html_files/$fileMd5/page$pageNum.html";

    # Loading conflicts json.
    my $conflictsJson;
    open my $in, '<:utf8', 'public/doc/pfizer_trials/josh_to_local_report.json';
    while (<$in>) {
        $conflictsJson .= $_;
    }
    close $in;
    $conflictsJson = decode_json($conflictsJson);
    my %conflictsJson = %$conflictsJson;
    %conflictsJson = %{$conflictsJson{$subjectId}};
    delete $conflictsJson{'xpt'};
    say "pdfFile : $pdfFile";
    # next;
    my %languages = ();
    $languages{'fr'} = 'French';
    $languages{'en'} = 'English';
    open my $in2, '<:utf8', $htmlFileLocal;
    my $content;
    while (<$in2>) {
        $content .= $_;
    }
    close $in2;
    $content =~ s/src="page$pageNum\.png"/src="\/pfizer_documents\/pdf_to_html_files\/$fileMd5\/page$pageNum\.png"/;
    $content =~ s/$subjectId/<span style="background:yellow">$subjectId<\/span>/;
    my $pdfFileName = "pfizer_documents/native_files/$pdfFile";
    my $totalPages     = keys %{$conflictsJson{'pdf'}->{$pdfFile}->{'pages'}};
    die unless $totalPages;
    my $p = 0;
    my $fN = 0;
    my ($formerPageNum, $nextPageNum, $currentPNum);
    for my $pN (sort{$a <=> $b} keys %{$conflictsJson{'pdf'}->{$pdfFile}->{'pages'}}) {
        $p++;
        if ($pN == $pageNum) {
            $formerPageNum  = $fN;
            $currentPNum = $p;
        } else {
            if ($currentPNum) {
                $nextPageNum   = $pN;
                last;
            }
        }
        $fN = $pN;
    }
    $self->render(
        conflictsJson   => \%conflictsJson,
        currentLanguage => $currentLanguage,
        pdfFileName     => $pdfFileName,
        subjectId       => $subjectId,
        content         => $content,
        fileNum         => $fileNum,
        fileMd5         => $fileMd5,
        pdfFile         => $pdfFile,
        pageNum         => $pageNum,
        currentPNum     => $currentPNum,
        totalPages      => $totalPages,
        formerPageNum   => $formerPageNum,
        nextPageNum     => $nextPageNum,
        languages       => \%languages
    );
}

1;
