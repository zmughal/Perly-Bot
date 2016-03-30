use v5.22;
use feature qw(signatures postderef);
no warnings qw(experimental::signatures experimental::postderef);

package Perly::Bot::Post;

use Perly::Bot::CommonSetup;

use namespace::autoclean;
use Data::Dumper;
use HTML::Entities;
use List::Util qw(sum any);

use base 'Class::Accessor';
__PACKAGE__->mk_accessors(
  qw/url title description datetime proxy delay_seconds twitter feed/);

my $logger = Log::Log4perl->get_logger();

=encoding utf8

=head1 NAME

Perly::Bot::Post - process a social media post

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 FUNCTIONS

=head2 clean_url

Removes the query component of the url. This is to reduce the risk of posting duplicate urls with different query parameters.

=cut

sub clean_url ( $self, $url ) {
  my $uri = Mojo::URL->new($url);
  return $uri->scheme . '://' . $uri->host . $uri->path;
}

=head2 root_url

Returns the clean url, if the blog post url is a proxy, it will follow the proxy url and return the ultimate location the URL redirects to.

=cut

sub root_url ( $self ) {
  return $self->clean_url( $self->url ) unless $self->proxy;

  # if we've already retrieved the root url, don't pull it again
  return $self->{_root_url} if exists $self->{_root_url};

  if ( my $response = Perly::Bot::UserAgent->get_user_agent->get( $self->url ) ) {
    my $location = $response->headers->header( 'Location' );

    my $url = do {
		if( my $location = $response->headers->header( 'Location' ) ) {
			$logger->debug( sprintf "Location is [%s]", $location );
			$location;
			}
		else {
			$logger->debug( sprintf "No Location header from [%s]", $self->title );
			$self->url;
			}
		};

    $self->{_root_url} = $self->clean_url( $url );
    return $self->{_root_url};
  }
  else {
    $logger->logcroak( sprintf "Error requesting [%s] [%s] [%s]",
    	$response->{url}, $response->code, $response->message
    );
  }
}

=head2 decoded_title

Returns the blog post title decoded from html using L<HTML::Entities>. This is required because some titles have HTML encoded characters in them.

=cut

sub decoded_title ( $self ) { decode_entities( $self->title ) }

=head2 should_emit

The logic to decide if a blog post should be emitted or not. This is:

- if the post is recent
- not too new to exceed the delay (to allow authors to post their own links)
- it looks Perl-related and is not already posted

Feel free to subclass and override this logic with your own needs for a particular
post type!

=cut

sub _content_exclusion_methods ( $self ) {
	qw(
	has_no_perlybot_tag
	has_no_perlybot_comment
  	);
  	}

sub _content_metric_methods ( $self ) {
	qw(
  	description_length
  	description_looks_perly
  	description_author
  	perly_links
  	keywords
  	);
  	}

sub fails_by_policy ( $post ) {
	my $config = Perly::Bot::Config->get_config;
	my $cache  = $config->cache;
	my $time_now = gmtime;

	my $policy = {
		fresh   => ($post->datetime > $time_now - $post->age_threshold_secs) ? 0 : 1,
		embargo => ($time_now - $post->datetime > $post->delay_seconds)      ? 2 : 0,
		cached  => $cache->has_posted($post) ? 4 : 0,
		};

	$post->{policy} = $policy;
	$post->{policy}{_sum} = sum( values %$policy );

    return $post->{policy}{_sum};
	}

sub threshold ( $self ) { 2 }

sub should_emit ( $post ) {
  my $config = Perly::Bot::Config->get_config;

  # these checks are for non-content things we configured
  return 0 if $post->fails_by_policy;

  # these checks are for things that absolutely exclude the post
  # no matter what else is going on
  my @killed = grep { $post->$_() } $post->_content_exclusion_methods;
  $post->{killed} = \@killed;
  return 0 if @killed;

  # these checks are for things that absolutely exclude the post
  # no matter what else is going on
  my %points = map { $_, $post->$_() // 0 } $post->_content_metric_methods;
  $post->{points} = \%points;

  my $points = sum( values %points );

  return 1 if $points >= $post->threshold;

  return 0;
}

=head2 age_threshold_secs

Returns the configured age_threshold_secs value. You can override this
to decide a value based on anything you like.

=cut

sub age_threshold_secs { Perly::Bot::Config->get_config->age_threshold_secs }

=head2 looks_perly( POST )

Returns true if the post looks like it's about Perl. Since it's a method
you can override this in specialized post types.

=cut

sub looks_perly ( $post, $scalar_ref ) {
	state $looks_perly =
		qr/\b(?:perl|perl6|cpan|cpanm|moose|metacpan|module|timtowdi|yapc|\:\:)\b/i;

	$$scalar_ref =~ $looks_perly;
	}

sub has_no_perlybot_tag     ( $self ) { 0 }
sub has_no_perlybot_comment ( $self ) { 0 }

sub description_length      ( $self ) { ( length( $self->description ) / 1000 ) % 3 }
sub description_looks_perly ( $self ) { $self->looks_perly( \ $self->description ) }
sub description_author      ( $self ) { 0 }
sub perly_links             ( $self ) { 0 }
sub keywords                ( $self ) { 0 }

sub clone ( $self ) {
	state $storable = require Storable;
	my $clone = Storable::dclone( $self );
	}


sub dump ( $self ) {
	my $clone = $self->clone;
	$clone->{description} =~ s/ \A \s+ //x;
	$clone->{description} = substr $clone->{description}, 0, 50;
	$clone->{description} =~ s/ \s+ \z//x;
	$clone->{description} =~ s/ \v+ / /x;

	$clone->{datetime} = '...';

	Dumper( $clone );
	}

=head1 TO DO

=head1 SEE ALSO

=head1 SOURCE AVAILABILITY

This source is part of a GitHub project.

	https://github.com/dnmfarrell/Perly-Bot

=head1 AUTHOR

David Farrell C<< <dfarrell@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright © 2015, David Farrell C<< <dfarrell@cpan.org> >>. All rights reserved.

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
