WebTek::DB->DESTROY;

my $deamons = config('async')->{'deamons'};
my $dir = config('async')->{'dir'};

mkdir $dir unless -d $dir;
chmod 0777, $dir;

foreach my $i (1 .. $deamons) {
   mkdir "$dir/$i" unless -d "$dir/$i";
   chmod 0777, "$dir/$i";

   unless (fork) {
      #... reinit DB connection
      while (1) {
         foreach my $file (`ls $dir/$i | sort -n`) {
            if ($file =~ /^\d+\n$/) {
               chop $file;
               log_info "running job $dir/$i/$file";
               WebTek::Util::write("$dir/$i/working", '');
               #... do job
               my $job = struct(WebTek::Util::slurp "$dir/$i/$file");
               my ($class, $method) = ($job->{'class'}, $job->{'method'});
               eval { $class->$method(@{$job->{'args'}}) };
               if ($@) {
                  log_error "  -> error during job $dir/$i/$file: $@";
                  log_error "  -> create error-file $dir/$i/error-$file";
                  my $error = { %$job, 'error' => "$@" };
                  WebTek::Util::write("$dir/$i/error-$file", struct($error));
               }
               #... cleanup
               unlink "$dir/$i/working";
               unlink "$dir/$i/$file";
               log_info "finish job $dir/$i/$file";
            }
         }
         sleep 1;         
      }
   }
}

wait foreach (1 .. $deamons);
