package Retry::Policy;

use strict;
use warnings;

our $VERSION = '0.01';

use Time::HiRes qw(usleep);
use Try::Tiny qw(try catch);

sub new {
    my ($class, %args) = @_;

    my $self = bless {
        max_attempts  => defined $args{max_attempts}  ? $args{max_attempts}  : 5,
        base_delay_ms => defined $args{base_delay_ms} ? $args{base_delay_ms} : 100,
        max_delay_ms  => defined $args{max_delay_ms}  ? $args{max_delay_ms}  : 10_000,
        jitter        => defined $args{jitter}        ? $args{jitter}        : 'full',  # none|full
        strategy      => defined $args{strategy}      ? $args{strategy}      : 'exponential',
        retry_on      => $args{retry_on},  # optional coderef
        on_retry      => $args{on_retry},  # optional coderef
    }, $class;

    _validate($self);
    return $self;
}

sub run {
    my ($self, $code) = @_;
    die "run() requires a coderef\n" if ref($code) ne 'CODE';

    my $attempt  = 0;
    my $last_err;

    while ($attempt < $self->{max_attempts}) {
        $attempt++;

        my ($ok, $result);
        try {
            $result = $code->($attempt);
            $ok = 1;
        }
        catch {
            $last_err = $_;
            $ok = 0;
        };

        return $result if $ok;

        last if $attempt >= $self->{max_attempts};
        last if !$self->should_retry($last_err, $attempt);

        my $delay_ms = $self->delay_ms($attempt);

        if (ref($self->{on_retry}) eq 'CODE') {
            $self->{on_retry}->(
                attempt  => $attempt,
                error    => "$last_err",
                delay_ms => $delay_ms,
            );
        }

        usleep($delay_ms * 1000);
    }

    die $last_err;
}

sub should_retry {
    my ($self, $err, $attempt) = @_;

    if (ref($self->{retry_on}) eq 'CODE') {
        return $self->{retry_on}->($err, $attempt) ? 1 : 0;
    }

    return 1; # default: retry on any exception
}

sub delay_ms {
    my ($self, $attempt) = @_;

    my $base = $self->{base_delay_ms};
    my $max  = $self->{max_delay_ms};

    my $raw;
    if ($self->{strategy} eq 'exponential') {
        $raw = $base * (2 ** ($attempt - 1));
    } else {
        die "Unsupported strategy: $self->{strategy}\n";
    }

    $raw = $max if $raw > $max;

    if ($self->{jitter} eq 'none') {
        return int($raw);
    }
    if ($self->{jitter} eq 'full') {
        return int(rand($raw + 1));
    }

    die "Unsupported jitter: $self->{jitter}\n";
}

sub _validate {
    my ($self) = @_;

    for my $k (qw(max_attempts base_delay_ms max_delay_ms)) {
        die "$k must be a positive integer\n"
            if !defined($self->{$k}) || $self->{$k} !~ /^\d+$/ || $self->{$k} <= 0;
    }

    die "max_delay_ms must be >= base_delay_ms\n"
        if $self->{max_delay_ms} < $self->{base_delay_ms};

    die "jitter must be 'none' or 'full'\n"
        if $self->{jitter} ne 'none' && $self->{jitter} ne 'full';

    die "strategy must be 'exponential'\n"
        if $self->{strategy} ne 'exponential';

    for my $k (qw(retry_on on_retry)) {
        next if !defined $self->{$k};
        die "$k must be a coderef\n" if ref($self->{$k}) ne 'CODE';
    }

    return 1;
}

1;

__END__

=head1 NAME

Retry::Policy - Simple retry wrapper with exponential backoff and jitter

=head1 SYNOPSIS

  use Retry::Policy;

  my $p = Retry::Policy->new(
      max_attempts  => 5,
      base_delay_ms => 100,
      max_delay_ms  => 10_000,
      jitter        => 'full',
  );

  my $value = $p->run(sub {
      my ($attempt) = @_;
      die "transient\n" if $attempt < 3;
      return "ok";
  });

=head1 DESCRIPTION

Small, dependency-light retry helper for backend and system code where
transient failures are expected.

=head1 LICENSE

Same terms as Perl itself.

=cut

