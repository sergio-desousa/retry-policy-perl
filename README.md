# NAME

Retry::Policy - Simple retry wrapper with exponential backoff and jitter

# SYNOPSIS

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

# DESCRIPTION

Small, dependency-light retry helper for backend and system code where
transient failures are expected.

# LICENSE

Same terms as Perl itself.
