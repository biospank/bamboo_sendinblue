defmodule Bamboo.SendinBlueAdapterTest do
  use ExUnit.Case
  alias Bamboo.Email
  alias Bamboo.Attachment
  alias Bamboo.SendinBlueAdapter

  @config %{adapter: SendinBlueAdapter, api_key: "123_abc"}
  @config_with_bad_key %{adapter: SendinBlueAdapter, api_key: nil}

  defmodule FakeSendinBlue do
    use Plug.Router

    plug(Plug.Parsers,
      # parsers: [:urlencoded, :multipart, :json],
      parsers: [:multipart, :json],
      pass: ["*/*"],
      json_decoder: Poison
    )

    plug(:match)
    plug(:dispatch)

    def start_server(parent) do
      Agent.start_link(fn -> Map.new() end, name: __MODULE__)
      Agent.update(__MODULE__, &Map.put(&1, :parent, parent))
      port = get_free_port()
      Application.put_env(:bamboo, :sendinblue_base_uri, "http://localhost:#{port}")
      Plug.Adapters.Cowboy.http(__MODULE__, [], port: port, ref: __MODULE__)
    end

    defp get_free_port do
      {:ok, socket} = :ranch_tcp.listen(port: 0)
      {:ok, port} = :inet.port(socket)
      :erlang.port_close(socket)
      port
    end

    def shutdown do
      Plug.Adapters.Cowboy.shutdown(__MODULE__)
    end

    post "/v2.0/email" do
      case Map.get(conn.params, "from") do
        "INVALID_EMAIL" -> conn |> send_resp(500, "Error!!") |> send_to_parent
        _ -> conn |> send_resp(200, "SENT") |> send_to_parent
      end
    end

    defp send_to_parent(conn) do
      parent = Agent.get(__MODULE__, fn set -> Map.get(set, :parent) end)
      send(parent, {:fake_sendinblue, conn})
      conn
    end
  end

  setup do
    FakeSendinBlue.start_server(self())

    on_exit(fn ->
      FakeSendinBlue.shutdown()
    end)

    :ok
  end

  test "raises if the api key is nil" do
    assert_raise ArgumentError, ~r/no API key set/, fn ->
      new_email(from: "foo@bar.com") |> SendinBlueAdapter.deliver(@config_with_bad_key)
    end

    assert_raise ArgumentError, ~r/no API key set/, fn ->
      SendinBlueAdapter.handle_config(%{})
    end
  end

  test "deliver/2 correctly formats reply-to from headers" do
    email = new_email(headers: %{"reply-to" => "foo@bar.com"})

    email |> SendinBlueAdapter.deliver(@config)

    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["replyto"] == "foo@bar.com"
  end

  test "deliver/2 sends the to the right url" do
    new_email() |> SendinBlueAdapter.deliver(@config)

    assert_receive {:fake_sendinblue, %{request_path: request_path}}

    assert request_path == "/v2.0/email"
  end

  test "deliver/2 sends from, html and text body, subject, and headers" do
    email =
      new_email(
        from: {"From", "from@foo.com"},
        subject: "My Subject",
        text_body: "TEXT BODY",
        html_body: "HTML BODY"
      )
      |> Email.put_header("Reply-To", {"ReplyTo", "reply@foo.com"})

    email |> SendinBlueAdapter.deliver(@config)

    assert_receive {:fake_sendinblue, %{params: params, req_headers: headers}}

    assert Enum.at(params["from"], 0) == email.from |> elem(1)
    assert Enum.at(params["from"], 1) == email.from |> elem(0)
    assert params["subject"] == email.subject
    assert params["text"] == email.text_body
    assert params["html"] == email.html_body
    assert Enum.member?(headers, {"api-key", @config[:api_key]})
  end

  test "deliver/2 correctly formats recipients" do
    email =
      new_email(
        to: [{"ToName", "to@bar.com"}, {nil, "noname@bar.com"}],
        cc: [{"CC1", "cc1@bar.com"}, {"CC2", "cc2@bar.com"}],
        bcc: [{"BCC1", "bcc1@bar.com"}, {"BCC2", "bcc2@bar.com"}]
      )

    email |> SendinBlueAdapter.deliver(@config)

    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == %{"to@bar.com" => "ToName", "noname@bar.com" => nil}
    assert params["cc"] == %{"cc1@bar.com" => "CC1", "cc2@bar.com" => "CC2"}
    assert params["bcc"] == %{"bcc1@bar.com" => "BCC1", "bcc2@bar.com" => "BCC2"}
  end

  test "deliver/2 correctly formats DATA attachments" do
    email =
      new_email(
        to: "noname@bar.com",
        attachments: [
          %Attachment{
            data: File.read!("./test/support/attachment.png"),
            content_type: "image/png",
            filename: Path.basename("attachment1.png")
          },
          %Attachment{
            data: File.read!("./test/support/attachment.png"),
            content_type: "image/png",
            filename: Path.basename("attachment2.png")
          }
        ]
      )

    email |> SendinBlueAdapter.deliver(@config)
    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == %{"noname@bar.com" => nil}

    assert params |> get_in(["attachment", "attachment1.png"]) ==
             File.read!("./test/support/attachment.png") |> Base.encode64()

    assert params |> get_in(["attachment", "attachment2.png"]) ==
             File.read!("./test/support/attachment.png") |> Base.encode64()
  end

  defp new_email(attrs \\ []) do
    Keyword.merge([from: "foo@bar.com", to: []], attrs)
    |> Email.new_email()
    |> Bamboo.Mailer.normalize_addresses()
  end
end
