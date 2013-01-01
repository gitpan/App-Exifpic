package App::Exifpic;
use 5.010;
use strict;
use warnings;
use threads;
use Thread::Queue;
use autodie;
use Image::ExifTool;
use Imager;
use File::Slurp qw(read_file);

use constant EXIT_SUCCESS => 0;

# ABSTRACT: Extract embedded jpegs from RAW files

our $VERSION = '0.01'; # VERSION: Generated by DZP::OurPkg:Version


# Run our application...


sub run {
    my ($self) = shift;
    # Imager needs to be preloaded if we're using threads.
    Imager->preload;

    # Right now we treat everything as a file to process...
    my $work_queue = Thread::Queue->new;
    $work_queue->enqueue(@_);
    $work_queue->end;

    # Spawn our threads, each of which will process files until we're done.

    my @threads;
    my $cores = $self->get_cores();

    # TODO: This could look less ugly
    for (1..$cores) {
        push(@threads,
            threads->create( sub {
                while (my $src = $work_queue->dequeue) {
                    $self->process_image($src);
                }
            })
        );
    }

    # Join threads.
    foreach my $thread (@threads) { $thread->join; }

    return EXIT_SUCCESS;
}


sub process_image {
    my ($self, $raw) = @_;

    my ($new) = $raw =~ m{(.*).CR2$}i;

    next if not $new;   # Skip non-CR2 files
    $new .= ".jpg";

    say "$raw -> $new...";

    my $exiftool = Image::ExifTool->new;

    my $exif = $exiftool->ImageInfo($raw, [qw(PreviewImage Orientation)], { Binary => 1 });

    my ($rotation) = ( $exif->{Orientation} =~ /(\d+)/ );

    $rotation ||= 0;

    my $img = Imager->new();
    $img->read(data => ${$exif->{PreviewImage}})
        or die $img->errstr;

    $img
        ->scale(type=>'min', xpixels=>2048, ypixels=>2048)
        ->rotate(degrees => $rotation)
        ->write(file=>$new, type=>'jpeg', jpegquality=>100)
    ;

    # Add EXIF info back in to the new file.

    $exiftool->SetNewValuesFromFile($raw);
    $exiftool->WriteInfo($new);

    return;
}


sub get_cores {

    # This only works on systems with a /proc/cpuinfo

    my $cpuinfo = read_file("/proc/cpuinfo");

    my ($cores) = $cpuinfo =~ m{.*processor\s*:\s*(?<cores>\d+)}msi;
    $cores++;

    return $cores;
}


1;

__END__

=pod

=head1 NAME

App::Exifpic - Extract embedded jpegs from RAW files

=head1 VERSION

version 0.01

=head1 DESCRIPTION

The guts of the L<exifpic> command line utility.

=head1 METHODS

=head2 run

    App::Exifpic->run(@ARGV);

Runs the application. Assumes all arguments are filenames to be processed.

=head2 process_image

    App::Exifpic->process_image($filename);

Extracts the embedded jpeg from the specified file, copying the metadata,
and writing the results to the same filename, but with a .jpg extension.

=head2 get_cores

    my $cores = App::Exifpic->get_cores;

Returns the number of cores on this machine.  Assumes the
F</proc/cpuinfo> file exists.

=head1 BUGS

All of them.  Patches seriously welcome.  Use the repo at
L<https://github.com/pfenwick/app-exifpic> and send me pull requests.

=head1 AUTHOR

Paul Fenwick <pjf@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Paul Fenwick.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut