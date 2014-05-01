#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use AnyEvent;
use FindBin;
use Log::Minimal;
use Unruly;
use URL::Encode qw/url_encode_utf8/;
use Web::Query;
use Text::MeCab;

use constant {
    WIKIPEDIA_BASE_URL => 'http://ja.wikipedia.org/wiki/',
    CONTENT_NODE       => 'div#mw-content-text p b',
};

my $conf = do "$FindBin::Bin/../config.pl";
my $YANCHA_URL = $conf->{YANCHA_URL};

my $ur = Unruly->new(
    url  => $YANCHA_URL,
    tags => {PUBLIC => 1}
);

$ur->login('chiezo');

my $cv = AnyEvent->condvar;

$ur->run(sub {
    my ($client, $socket) = @_;
    $socket->on('user message' => sub {
        my ($socket_info, $message) = @_;

        my @tags = @{$message->{tags}};
        my $message_text = $message->{text};
        if ($message->{text} =~ /^w\s(.+)\s#/) {
            my $word = $1;
            my $url  = WIKIPEDIA_BASE_URL . url_encode_utf8($word);

            my $q = Web::Query->new_from_url($url);
            unless ($q) {
                critf("Cannot get a resource from %s: %s", $url);
                $ur->post("そんな用語を説明してるページないです: $word", @tags);
                return;
            }

            my $text = $q->find(CONTENT_NODE)->first->parent->first->text;
            unless ($text) {
                critf("Cannot get the content text: %s", CONTENT_NODE);
                $ur->post("多分WikipediaのDOMの構造変わった", @tags);
                return;
            }

            my $post_text = sprintf("%s %s", substr($text, 0, 100), $url);
            $ur->post($post_text, @tags);
        }
        elsif ($message->{text} =~ /^mecab!\s(.+)\s#/) {
            my $word      = $1;
            my $post_text = '';

            my $mecab = Text::MeCab->new;
            for (my $node = $mecab->parse(); $node->surface; $node = $node->next) {
                $post_text .= $node->surface . "\t";
                $post_text .= $node->feature . "\n";
            }
            $ur->post($post_text, @tags);
        }
    });
});

$cv->wait;
