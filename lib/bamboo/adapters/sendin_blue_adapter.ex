defmodule Bamboo.SendinBlueAdapter do
  @moduledoc """
  Sends email using SendinBlue's JSON API v2.0.

  Use this adapter to send emails through SendinBlue's API. Requires that an API
  key is set in the config.

  If you would like to add a replyto header to your email, then simply pass it in
  using the header property or put_header function like so:

      put_header("reply-to", "foo@bar.com")

  ## Example config

      # In config/config.exs, or config.prod.exs, etc.
      config :my_app, MyApp.Mailer,
        adapter: Bamboo.SendinBlueAdapter,
        api_key: "my_api_key"

      # Define a Mailer. Maybe in lib/my_app/mailer.ex
      defmodule MyApp.Mailer do
        use Bamboo.Mailer, otp_app: :my_app
      end
  """

  @default_base_uri "https://api.sendinblue.com"
  @send_message_path "/v2.0/email"
  @behaviour Bamboo.Adapter

  alias Bamboo.Email
  alias Bamboo.Attachment

  defmodule ApiError do
    defexception [:message]

    def exception(%{message: message}) do
      %ApiError{message: message}
    end

    def exception(%{params: params, response: response}) do
      filtered_params = params |> Plug.Conn.Query.decode() |> Map.put("key", "[FILTERED]")

      message = """
      There was a problem sending the email through the SendinBlue API v2.0.

      Here is the response:

      #{inspect(response, limit: :infinity)}

      Here are the params we sent:

      #{inspect(filtered_params, limit: :infinity)}

      If you are deploying to Heroku and using ENV variables to handle your API key,
      you will need to explicitly export the variables so they are available at compile time.
      Add the following configuration to your elixir_buildpack.config:

      config_vars_to_export=(
        DATABASE_URL
        SENDINBLUE_API_KEY
      )
      """

      %ApiError{message: message}
    end
  end

  def deliver(email, config) do
    api_key = get_key(config)
    body = email |> to_sendinblue_body |> Poison.encode!()
    url = [base_uri(), @send_message_path]

    case :hackney.post(url, headers(api_key), body, [:with_body]) do
      {:ok, status, _headers, response} when status > 299 ->
        raise(ApiError, %{params: body, response: response})

      {:ok, status, headers, response} ->
        %{status_code: status, headers: headers, body: response}

      {:error, reason} ->
        raise(ApiError, %{message: inspect(reason)})
    end
  end

  @doc false
  def handle_config(config) do
    if config[:api_key] in [nil, ""] do
      raise_api_key_error(config)
    else
      config
    end
  end

  def supports_attachments?, do: true

  defp get_key(config) do
    case Map.get(config, :api_key) do
      nil -> raise_api_key_error(config)
      key -> key
    end
  end

  defp raise_api_key_error(config) do
    raise ArgumentError, """
    There was no API key set for the SendinBlue adapter.

    * Here are the config options that were passed in:

    #{inspect(config)}
    """
  end

  defp headers(api_key) do
    [{"Content-Type", "application/json"}, {"api-key", api_key}]
  end

  defp to_sendinblue_body(%Email{} = email) do
    %{}
    |> put_from(email)
    |> put_to(email)
    |> put_reply_to(email)
    |> put_cc(email)
    |> put_bcc(email)
    |> put_subject(email)
    |> put_html_body(email)
    |> put_text_body(email)
    |> put_attachments(email)
  end

  defp put_from(body, %Email{from: {nil, address}}), do: Map.put(body, :from, [address, ""])

  defp put_from(body, %Email{from: {name, address}}) do
    body
    |> Map.put(:from, [address, name])
  end

  defp put_to(body, %Email{to: to}) do
    body |> put_addresses(:to, address_map(to))
  end

  defp put_cc(body, %Email{cc: []}), do: body

  defp put_cc(body, %Email{cc: cc}) do
    body |> put_addresses(:cc, address_map(cc))
  end

  defp put_bcc(body, %Email{bcc: []}), do: body

  defp put_bcc(body, %Email{bcc: bcc}) do
    body |> put_addresses(:bcc, address_map(bcc))
  end

  defp put_subject(body, %Email{subject: subject}), do: Map.put(body, :subject, subject)

  defp put_html_body(body, %Email{html_body: nil}), do: body
  defp put_html_body(body, %Email{html_body: html_body}), do: Map.put(body, :html, html_body)

  defp put_text_body(body, %Email{text_body: nil}), do: body
  defp put_text_body(body, %Email{text_body: text_body}), do: Map.put(body, :text, text_body)

  defp put_reply_to(body, %Email{headers: %{"reply-to" => reply_to}} = _email) do
    Map.put(body, :replyto, reply_to)
  end

  defp put_reply_to(body, _), do: body

  defp put_addresses(body, field, addresses), do: Map.put(body, field, addresses)

  defp base_uri do
    Application.get_env(:bamboo, :sendinblue_base_uri) || @default_base_uri
  end

  defp put_attachments(body, %Email{attachments: []}), do: body

  defp put_attachments(body, %Email{attachments: atts}) do
    attachments =
      atts
      |> Enum.reduce(%{}, fn attachment, acc ->
        put_attachment(acc, attachment)
      end)

    Map.put(body, :attachment, attachments)
  end

  defp put_attachment(acc, %Attachment{data: data, filename: filename}) do
    Map.put(acc, filename, Base.encode64(data))
  end

  defp address_map(addresses) when is_list(addresses) do
    addresses
    |> Enum.reduce(%{}, fn {name, address}, acc ->
      Map.put(acc, address, name)
    end)
  end
end
