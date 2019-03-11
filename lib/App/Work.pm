unit module App::Work;

my $work_dir = %*ENV<HOME>.IO.child('.work');
$work_dir.d or $work_dir.mkdir;

my $logfile   = $work_dir.child('log');
my $notesfile = $work_dir.child('notes');

sub roundings(Duration:D $dur) {
    my $minutes    = minutes($dur);
    my $half-hours = Int($minutes / 30);
    return ($half-hours X+ (-1, 0, 1)).map(* * 30);
}

sub started {
    return unless $work_dir.child('started').f;

    my $started = $work_dir.child('started').slurp.Int;
    return DateTime.new($started).local;
}

sub minutes(Duration:D $dur) {
    return Int($dur / 60);
}

multi hm(DateTime:D $when) {
    return sprintf("%d:%02d", $when.hour, $when.minute);
}

multi hm(Duration:D $dur) {
    hm(minutes($dur))
}

multi hm(Int:D $minutes is copy) {
    my $hours = Int($minutes / 60);
    return sprintf("%d:%02d", $hours, $minutes % 60);
}

#| display current status
multi MAIN() is export {
    MAIN('status')
}

#| display current status
multi MAIN('status') is export {
    if $work_dir.child('started').f {
        my $since   = started;
        my $elapsed = DateTime.now - $since;

        say "You've been working for {hm($elapsed)} (since {hm($since)})";

        if $notesfile.f {
            say "Current work notes:";
            say slurp($notesfile);
        }
    } else {
        say "Work is currently not being done";
    }
}

#| add a note to currently tracked work
multi MAIN('note') is export {
    my $note = prompt("Enter your note: ");
    given open($work_dir.child('notes'), :a) {
        .say($note);
        .close();
    }
    say "Note noted";
}

#| start time tracking
multi MAIN('start') is export {
    my $now = DateTime.now;

    if started() {
        return MAIN('status');
    }

    $work_dir.child('started').spurt($now.posix);
    say "Work started at {hm($now)}";
}

#| abort time tracking (does not log time spent)
multi MAIN('abort') is export {
    MAIN('status');
    $work_dir.child('started').unlink;
    say "I just threw all that away";
}

#| show work log for current/last month
multi MAIN('log', Bool :$last, Bool :$week) is export {
    say "Work log for {$last ?? 'last' !! 'current'} {$week ?? 'week' !! 'month'}:\n";

    my ($start, $end);
    if $week {
        $start = Date.today.truncated-to('week');
        if $last {
            $start .= earlier(:1week);
        }
        $end = $start.later(:1week);
    } else {
        $start = Date.today.truncated-to('month');
        if $last {
            $start .= earlier(:1month);
        }
        $end = $start.later(:1month);
    }

    my %projects;
    
    for $logfile.lines {
        my ($date, $hours, $project, $notes) = .split(',', 4);
        $date = Date.new($date);
        if $start <= $date < $end {
            %projects{$project}.push($hours => $notes);
        }
    }

    for %projects.kv -> $project, @work {
        say "Project $project:";
        my $total-minutes = 0;
        for @work -> $day {
            printf "\t[%s]\t%s\n", $day.key, $day.value;
            my ($hours, $minutes) = $day.key.split(':');
            $total-minutes += $minutes + $hours * 60;
        }
        say "\n\tTotal time spent: {hm($total-minutes)}";
    }
}

#| finish current time tracking and log the time spent
multi MAIN('finish') is export {
    my $started = started;
    my $ended   = DateTime.now;

    my @candidates = roundings($ended - $started).map({ hm($_) });
    say "Job well done! How much time do you want to log?";
    say "1) @candidates[0]";
    say "2) @candidates[1] (default)";
    say "3) @candidates[2]";
    my $choice = prompt("Your choice: ");
    if $choice == any(1, 2, 3) {
        $choice = @candidates[$choice - 1];
    } else {
        $choice = @candidates[1];
    }

    my $project = prompt("What project was it? ");

    my $notes = '';
    if $notesfile.f {
        $notes = slurp($notesfile);
        $notes    ~~ s:g/\n/;/;
    }

    given open($logfile, :a) {
        .say("{Date.today},$choice,$project,$notes");
        .close();
    }

    say "Work logged";
    $work_dir.child('started').unlink;
    $notesfile.unlink;
}
