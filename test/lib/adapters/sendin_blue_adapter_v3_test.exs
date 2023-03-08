defmodule Bamboo.SendinBlueAdapterV3Test do
  use ExUnit.Case
  alias Bamboo.Email
  alias Bamboo.Attachment
  alias Bamboo.SendinBlueAdapterV3
  alias Bamboo.SendinBlueHelper

  @config %{adapter: SendinBlueAdapterV3, api_key: "123_abc"}
  @config_with_bad_key %{adapter: SendinBlueAdapterV3, api_key: nil}

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

    post "/v3/smtp/email" do
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

  defp new_email(attrs \\ []) do
    Keyword.merge([from: "foo@bar.com", to: []], attrs)
    |> Email.new_email()
    |> Bamboo.Mailer.normalize_addresses()
  end

  test "raises if the api key is nil" do
    assert_raise ArgumentError, ~r/no API key set/, fn ->
      new_email(from: "foo@bar.com") |> SendinBlueAdapterV3.deliver(@config_with_bad_key)
    end

    assert_raise ArgumentError, ~r/no API key set/, fn ->
      SendinBlueAdapterV3.handle_config(%{})
    end
  end

  test "deliver/2 correctly formats reply-to from headers" do
    email = new_email(headers: %{"reply-to-email" => "foo@bar.com", "reply-to-name" => "Foo"})

    email |> SendinBlueAdapterV3.deliver(@config)

    assert_receive {:fake_sendinblue, %{params: params}}
    assert %{"email" => "foo@bar.com", "name" => "Foo"} = params["replyTo"]
  end

  test "deliver/2 sends the to the right url" do
    new_email() |> SendinBlueAdapterV3.deliver(@config)

    assert_receive {:fake_sendinblue, %{request_path: request_path}}

    assert request_path == "/v3/smtp/email"
  end

  test "deliver/2 sends the to the right url for templates" do
    new_email() |> SendinBlueHelper.template("hello") |> SendinBlueAdapterV3.deliver(@config)

    assert_receive {:fake_sendinblue, %{request_path: request_path}}

    assert request_path == "/v3/smtp/email"
  end

  test "deliver/2 sends from, html and text body, subject, and headers" do
    email =
      new_email(
        from: {"From", "from@foo.com"},
        subject: "My Subject",
        text_body: "TEXT BODY",
        html_body: "HTML BODY"
      )
      |> Email.put_header("reply-to-name", "Foo")
      |> Email.put_header("reply-to-email", "foo@bar.com")

    email |> SendinBlueAdapterV3.deliver(@config)

    assert_receive {:fake_sendinblue, %{params: params, req_headers: headers}}
    assert params["sender"]["email"] == email.from |> elem(1)
    assert params["sender"]["name"] == email.from |> elem(0)
    assert params["subject"] == email.subject
    assert params["textContent"] == email.text_body
    assert params["htmlContent"] == email.html_body
    assert Enum.member?(headers, {"api-key", @config[:api_key]})
  end

  test "deliver/2 correctly formats recipients" do
    email =
      new_email(
        to: [{"ToName", "to@bar.com"}, {nil, "noname@bar.com"}],
        cc: [{"CC1", "cc1@bar.com"}, {"CC2", "cc2@bar.com"}],
        bcc: [{"BCC1", "bcc1@bar.com"}, {"BCC2", "bcc2@bar.com"}]
      )

    email |> SendinBlueAdapterV3.deliver(@config)

    assert_receive {:fake_sendinblue, %{params: params}}

    assert params["to"] == [
             %{"email" => "to@bar.com", "name" => "ToName"},
             %{"email" => "noname@bar.com"}
           ]

    assert params["cc"] == [
             %{"email" => "cc1@bar.com", "name" => "CC1"},
             %{"email" => "cc2@bar.com", "name" => "CC2"}
           ]

    assert params["bcc"] == [
             %{"email" => "bcc1@bar.com", "name" => "BCC1"},
             %{"email" => "bcc2@bar.com", "name" => "BCC2"}
           ]
  end

  test "deliver/2 puts template name and empty content" do
    email = SendinBlueHelper.template(new_email(), "hello")

    SendinBlueAdapterV3.deliver(email, @config)

    assert_receive {:fake_sendinblue, %{params: %{"templateId" => template_id,
       "params" => template_model}}}
    assert template_id == "hello"
    assert template_model == %{}
  end

  test "deliver/2 puts template name and content" do
    email = SendinBlueHelper.template(new_email(), "hello", [
      %{name: "example name", content: "example content"}
    ])

    SendinBlueAdapterV3.deliver(email, @config)

    assert_receive {:fake_sendinblue, %{params: %{"templateId" => template_id,
       "params" => template_model}}}
    assert template_id == "hello"
    assert template_model == [%{"content" => "example content",
      "name" => "example name"}]
  end

  test "deliver/2 puts tag param" do
    new_email()
      |> SendinBlueHelper.tag("some_tag")
      |> SendinBlueAdapterV3.deliver(@config)

    assert_receive {:fake_sendinblue, %{params: %{"tags" => ["some_tag"]}}}
  end

  test "deliver/2 puts multiple tags param" do
    email = new_email()
            |> SendinBlueHelper.tag("tag2")
            |> SendinBlueHelper.tag("tag1")

    SendinBlueAdapterV3.deliver(email, @config)

    assert_receive {:fake_sendinblue, %{params: %{"tags" => ["tag1", "tag2"]}}}
  end

  test "deliver/2 correctly formats DATA attachment from local path even if filename is missing" do
    email =
      new_email(
        to: "noname@bar.com",
        attachments: [
          Attachment.new("./test/support/attachment.png")
        ]
      )

    email |> SendinBlueAdapterV3.deliver(@config)
    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == [%{"email" => "noname@bar.com"}]

    assert params["attachment"] == [
             %{
               "content" => File.read!("./test/support/attachment.png") |> Base.encode64(),
               "name" => "attachment.png"
             }
           ]
  end

  test "deliver/2 correctly formats DATA attachment from contents, path when filename is missing" do
    email =
      new_email(
        to: "noname@bar.com",
        attachments: [
          %Attachment{
            path: "./test/support/attachment.png",
            data: File.read!("./test/support/attachment.png")
          }
        ]
      )

    email |> SendinBlueAdapterV3.deliver(@config)
    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == [%{"email" => "noname@bar.com"}]

    assert params["attachment"] == [
             %{
               "content" => File.read!("./test/support/attachment.png") |> Base.encode64(),
               "name" => "attachment.png"
             }
           ]
  end

  test "deliver/2 correctly formats DATA attachment from contents, filename" do
    email =
      new_email(
        to: "noname@bar.com",
        attachments: [
          %Attachment{
            filename: "attachment1.png",
            data: File.read!("./test/support/attachment.png")
          }
        ]
      )

    email |> SendinBlueAdapterV3.deliver(@config)
    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == [%{"email" => "noname@bar.com"}]

    assert params["attachment"] == [
             %{
               "content" => File.read!("./test/support/attachment.png") |> Base.encode64(),
               "name" => "attachment1.png"
             }
           ]
  end

  test "deliver/2 correctly formats DATA attachment from path" do
    email =
      new_email(
        to: "noname@bar.com",
        attachments: [Attachment.new("./test/support/attachment.png")]
      )

    email |> SendinBlueAdapterV3.deliver(@config)
    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == [%{"email" => "noname@bar.com"}]

    assert params["attachment"] == [
             %{
               "content" => File.read!("./test/support/attachment.png") |> Base.encode64(),
               "name" => "attachment.png"
             }
           ]
  end

  test "deliver/2 correctly formats LINK attachment from path, filename" do
    email =
      new_email(
        to: "noname@bar.com",
        attachments: [
          %Attachment{
            path: "https://www.coders51.com/img/logo-alt.png",
            filename: "attachment1.png"
          }
        ]
      )

    email |> SendinBlueAdapterV3.deliver(@config)
    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == [%{"email" => "noname@bar.com"}]

    assert params["attachment"] == [
             %{
               "url" => "https://www.coders51.com/img/logo-alt.png",
               "name" => "attachment1.png"
             }
           ]
  end

  test "deliver/2 correctly formats LINK attachment from path" do
    email =
      new_email(
        to: "noname@bar.com",
        attachments: [
          %Attachment{
            path: "https://www.coders51.com/img/logo-alt.png"
          }
        ]
      )

    email |> SendinBlueAdapterV3.deliver(@config)
    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == [%{"email" => "noname@bar.com"}]

    assert params["attachment"] == [
             %{
               "url" => "https://www.coders51.com/img/logo-alt.png",
               "name" => "logo-alt.png"
             }
           ]
  end

  test "deliver/2 correctly formats mixed DATA/LINK attachments" do
    email =
      new_email(
        to: "noname@bar.com",
        attachments: [
          Attachment.new("./test/support/attachment.png", filename: "attachment1.png"),
          %Attachment{path: "https://www.coders51.com/img/logo-alt.png"}
        ]
      )

    email |> SendinBlueAdapterV3.deliver(@config)
    assert_receive {:fake_sendinblue, %{params: params}}
    assert params["to"] == [%{"email" => "noname@bar.com"}]

    assert params["attachment"] == [
             %{
               "content" => File.read!("./test/support/attachment.png") |> Base.encode64(),
               "name" => "attachment1.png"
             },
             %{"name" => "logo-alt.png", "url" => "https://www.coders51.com/img/logo-alt.png"}
           ]
  end

  test "deliver/2 puts inline attachments" do
    email = SendinBlueHelper.template(new_email(), "hello", [
      %{name: "example name", content: "example content <img src=\"my-attachment\" />"}
    ])
    |> Email.put_attachment(Path.join(__DIR__, "../../support/attachment.png"))

    SendinBlueAdapterV3.deliver(email, @config)

    assert_receive {
      :fake_sendinblue,
      %{
        params: %{
          "attachment" => [
            %{
              "content" => "iVBORw0KGgoAAAANSUhEUgAAAGQAAABkCAIAAAD/gAIDAAABg2lDQ1BJQ0MgcHJvZmlsZQAAKJF9kT1Iw0AcxV9Ti1JaHOwg4pChOlkQFXHUKhShQqgVWnUwufQLmjQkKS6OgmvBwY/FqoOLs64OroIg+AHi5uak6CIl/i8ptIjx4Lgf7+497t4BQrPKNKtnHNB028ykkmIuvyr2vkJACGEAUZlZxpwkpeE7vu4R4Otdgmf5n/tzRNWCxYCASDzLDNMm3iCe3rQNzvvEMVaWVeJz4jGTLkj8yHXF4zfOJZcFnhkzs5l54hixWOpipYtZ2dSIp4jjqqZTvpDzWOW8xVmr1ln7nvyFkYK+ssx1msNIYRFLkCBCQR0VVGEjQatOioUM7Sd9/EOuXyKXQq4KGDkWUIMG2fWD/8Hvbq3i5ISXFEkCoRfH+RgBeneBVsNxvo8dp3UCBJ+BK73jrzWBmU/SGx0tfgT0bwMX1x1N2QMud4DBJ0M2ZVcK0hSKReD9jL4pDwzcAuE1r7f2Pk4fgCx1lb4BDg6B0RJlr/u8u6+7t3/PtPv7AbeTclziFEqrAAAACXBIWXMAAA7EAAAOxAGVKw4bAAAAB3RJTUUH5QIFCgArZmj/VQAAAJ9JREFUeNrt0DEBAAAIAyC1f+dZwc8HItBJiptRIEuWLFmyZCmQJUuWLFmyFMiSJUuWLFkKZMmSJUuWLAWyZMmSJUuWAlmyZMmSJUuBLFmyZMmSpUCWLFmyZMlSIEuWLFmyZCmQJUuWLFmyFMiSJUuWLFkKZMmSJUuWLAWyZMmSJUuWAlmyZMmSJUuBLFmyZMmSpUCWLFmyZMlSIEvWtwXP8QPFWbLJBwAAAABJRU5ErkJggg==",
              "name" => "attachment.png"
            }
          ]
        }
      }
    }
  end
end
