# BambooSendinBlue

An Adapter for the [Bamboo](https://github.com/thoughtbot/bamboo) email app.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

1. Add bamboo_sendinblue to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:bamboo_sendinblue, "~> 0.1.0"}]
  end
  ```

2. Ensure bamboo is started before your application:

  ```elixir
  def application do
    [applications: [:bamboo]]
  end
  ```

3. Setup your SendinBlue configuration:

  ```elixir
  # In your config/config.exs file
  config :my_app, MyApp.Mailer,
    adapter: Bamboo.SendinBlueAdapter,
    api_key: "your-api-key"
  ```

4. Follow Bamboo [Getting Started Guide](https://github.com/thoughtbot/bamboo#getting-started)

## Contributing

Before opening a pull request you can open an issue if you have any question or need some guidance.

Here's how to setup the project:

```
$ git clone https://github.com/biospank/bamboo_sendinblue.git
$ cd bamboo_sendinblue
$ mix deps.get
$ mix test
```

Once you've made your additions and `mix test` passes, go ahead and open a Pull Request.

## TODO

1. Attachments

## License

Bamboo SendinBlueAdapter is released under [The MIT License (MIT)](https://opensource.org/licenses/MIT).
