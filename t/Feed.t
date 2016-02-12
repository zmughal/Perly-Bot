use strict;
use warnings;
use v5.10.1;
use Test::More 0.95;
use YAML::XS 'LoadFile';

my $feeds = LoadFile('t/test_feeds.yml');

my $class = 'Perly::Bot::Feed';

BEGIN {
package Log::Log4perl {
	no warnings 'redefine';
	sub AUTOLOAD   { __PACKAGE__ };
	}
$INC{'Log/Log4perl.pm'} = 'Feed.t';
}

use_ok($class) or BAIL_OUT( "$class did not load" );

for my $args (@$feeds)
{
  subtest $args->{url} => sub
  {
    my %args_copy = %$args;

	my $feed = eval { new_ok( $class, [ $args ] ) };

    if ($@ || !$feed)
    {
      diag "Unable to build feed, skipping tests $@\n";
      pass();
      return;
    }

    state $methods = [qw(url type date_name date_format media)];
    can_ok( $feed, @$methods );
    foreach my $method ( @$methods )
    {
      ok $feed->$method(), "$method returns something that is true (" . $feed->$method() . ")";
    }

    ok( $feed->type eq 'rss' || $feed->type eq 'atom' || $feed->type eq 'rdf', 'Feed type is either rss, atom or rdf (' . $feed->type . ')' );
    isa_ok $feed->media, ref [];

    like $feed->active, qr/^[01]$/, "active field is 0 or 1 (" . $feed->active . ")";
    like $feed->proxy, qr/^[01]$/, "proxy field is 0 or 1 (" . $feed->proxy . ")";
    like $feed->delay_seconds, qr/^[0-9]+$/, , "delay_seconds field is only digits (" . $feed->delay_seconds . ")";
  };
}

done_testing();
