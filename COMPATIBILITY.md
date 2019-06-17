# Compatibility

We aim for the Prometheus Ruby client to be compatible with all supported
versions of Ruby, across the MRI and JRuby platforms.

Any Ruby version that has not received an End-of-Life notice (e.g.
[this notice for Ruby 2.1](https://www.ruby-lang.org/en/news/2017/04/01/support-of-ruby-2-1-has-ended/))
is supported.

To ensure we're meeting these guidelines, we test the client against all
supported versions, as specified in our [build matrix](.travis.yml).

# Deprecation

Whenever a version of Ruby falls out of support we will mirror that change in
the Prometheus Ruby client by updating the build matrix and releasing a new
major version.

At that point we will close any issues that affect only the unsupported version,
and may choose to remove any workarounds from the code that are only necessary
for the unsupported version.

The major version bump signals the break in compatibility. If the client happens
to work on unsupported versions of Ruby this is by chance, and we wouldn't
consider that version to be officially supported.
