Panopticd
====

Panopticd is a anomaly log monitoring tool. Easy, simple, and lightweight.

## Description

## Requirement

* Perl (> 5.20)
  * Regexp::Assemble
  * MIME::EncWords
  * FindBin::libs

## Install

1. clone or unzip.

```
    % git clone https://github.com/frisky-gh/panopticd.git
```

2. setup rsyslog, syslog-ng or other logger to output logs
   into ./panopticd/spool/targetlog/ .

```
    ex) rsyslog.conf
    $FileCreateMode 0644
    $template SyslogDaily,"/home/frisky/panopticd/spool/targetlog/syslog_%$year%-%$month%-%$day%"
    *.* ?SyslogDaily
```

3. complete.

## Usage

1. copy well-known syslogs to ./panopticd/conf/pattern/ as sample.

```
    % cp ./syslog.1 ./panopticd/conf/pattern/syslog-wellknown.samplelog
```

2. build patterns and patternsets from sample logs.

```
    % ./panopticd/bin/panopticctl build
```

3. copy conf files from examples and configurate it.

```
    % cd ./panopticd/conf
    % cp delivery.conf.example delivery.conf
    % vi delivery.conf
    % cp generate_pattern.conf.example generate_pattern.conf
    % vi generate_pattern.conf
    (continue...)
```

4. startup panopticd.

```
    % ./panopticd/bin/panopticd start
```

## Licence

[MIT](https://github.com/frisky-gh/panopticd/blob/master/LICENSE)

## Author

[frisky-gh](https://github.com/frisky-gh)

