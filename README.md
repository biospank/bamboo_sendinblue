# BambooSendinBlue

An Adapter for the [Bamboo](https://github.com/thoughtbot/bamboo) email app.
Uses SendInBlue API v2.0 or v3.0. The 2.0 version sunset date [has been scheduled](https://developers.sendinblue.com/docs/migration-guide-for-api-v2-users-1) for June 25th 2021.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

1. Add bamboo_sendinblue to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:bamboo_sendinblue, "~> 0.3.0"}]
end
```

2. Ensure bamboo is started before your application:

```elixir
def application do
  [applications: [:bamboo]]
end
```

3. Setup your SendinBlue configuration:

For API v2

```elixir
# In your config/config.exs file (API v2)
config :my_app, MyApp.Mailer,
  adapter: Bamboo.SendinBlueAdapter,
  api_key: "your-api-V2-key"
```

For API v3

```elixir
# In your config/config.exs file (API v3)
config :my_app, MyApp.Mailer,
  adapter: Bamboo.SendinBlueAdapterV3,
  api_key: "your-api-V3-key"
```

Please take note that V2 API keys will not work with the V3 adapter and vice versa. Refer to [this page](https://help.sendinblue.com/hc/en-us/articles/209467485-What-s-an-API-key-and-how-can-I-get-mine-) for more information.

4. Follow Bamboo [Getting Started Guide](https://github.com/thoughtbot/bamboo#getting-started)

## V3 Adapter Example

```elixir
  import Bamboo.Email

  new_email(
    to: "noname@bar.com",
    cc: [{"Foo", "foo@bar.com"}, {"Another Foo", "foo2@bar.com"}],
    bcc: [{"Hidden foo", "hfoo@bar.com"}],
    attachments: [
      Bamboo.Attachment.new("./test/support/attachment.png", filename: "attachment1.png"),
      %Bamboo.Attachment{path: "<url>"}
    ]
  )
  |> put_header("reply-to-email", "noreply@bar.com")
  |> put_header("reply-to-name", "NoReply")
  |> MyApp.Mailer.deliver_now()
```

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

## License

Bamboo SendinBlueAdapter is released under [The MIT License (MIT)](https://opensource.org/licenses/MIT).
