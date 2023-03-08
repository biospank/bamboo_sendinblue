defmodule Bamboo.SendinBlueAdapterV3 do
  @moduledoc """
  Sends email using SendinBlue's JSON API v3.0.

  This module requires a v3 API key to work.

  Based on https://github.com/biospank/bamboo_sendinblue (the SendinBlue V2 API adapter)

  ## Reply-To field
  To set the reply-to field, use `put_header(email, "reply-to-email", "user@mail.com")` and optionally `put_header(email, "reply-to-name", "The Name")`

  ## Example config

      # In config/config.exs, or config.prod.exs, etc.
      config :my_app, MyApp.Mailer,
        adapter: Bamboo.SendinBlueAdapterV3,
        api_key: "my_api_key"

      # Define a Mailer. Maybe in lib/my_app/mailer.ex
      defmodule MyApp.Mailer do
        use Bamboo.Mailer, otp_app: :my_app
      end
  """
  @behaviour Bamboo.Adapter
  require Logger
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
      There was a problem sending the email through the SendinBlue API v3.0.

      Response:

      #{inspect(response, limit: :infinity)}

      Parameters:

      #{inspect(filtered_params, limit: :infinity)}
      """

      %ApiError{message: message}
    end
  end

  def supports_attachments?, do: true

  def deliver(email, config) do
    api_key = get_key(config)
    body = email |> to_sendinblue_body |> Poison.encode!()
    url = get_api_url()

    case :hackney.post(url, headers(api_key), body, [:with_body]) do
      {:ok, status, _headers, response} when status > 299 ->
        raise(ApiError, %{params: body, response: response})

      {:ok, status, headers, response} ->
        %{status_code: status, headers: headers, body: response}

      {:error, reason} ->
        Logger.warn("#{inspect({url, body})}")
        raise(ApiError, %{message: inspect(reason)})
    end
  end

  def handle_config(config) do
    if config[:api_key] in [nil, ""] do
      raise_api_key_error(config)
    else
      config
    end
  end

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
    |> put_sender(email)
    |> put_to(email)
    |> put_reply_to(email)
    |> put_cc(email)
    |> put_bcc(email)
    |> put_subject(email)
    |> put_html_body(email)
    |> put_text_body(email)
    |> put_attachments(email)
    |> put_template_params(email)
    |> put_tag_params(email)
  end

  defp put_sender(body, %Email{from: {nil, address}}) do
    body |> Map.put(:sender, %{email: address})
  end

  defp put_sender(body, %Email{from: {name, address}}) do
    body |> Map.put(:sender, %{email: address, name: name})
  end

  defp put_sender(body, %Email{from: address}) do
    body |> Map.put(:sender, %{email: address})
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

  defp put_html_body(body, %Email{html_body: html_body}),
    do: Map.put(body, :htmlContent, html_body)

  defp put_text_body(body, %Email{text_body: nil}), do: body

  defp put_text_body(body, %Email{text_body: text_body}),
    do: Map.put(body, :textContent, text_body)

  defp put_reply_to(body, %Email{headers: headers} = _email) do
    body |> put_reply_to_email(headers) |> put_reply_to_name(headers)
  end

  defp put_reply_to_email(body, %{"reply-to-email" => email}) do
    reply_to = body |> Map.get(:replyTo, %{}) |> Map.put(:email, email)
    Map.put(body, :replyTo, reply_to)
  end

  defp put_reply_to_email(body, _), do: body

  defp put_reply_to_name(body, %{"reply-to-name" => name}) do
    reply_to = body |> Map.get(:replyTo, %{}) |> Map.put(:name, name || "")
    Map.put(body, :replyTo, reply_to)
  end

  defp put_reply_to_name(body, _), do: body

  defp put_addresses(body, field, []), do: Map.delete(body, field)
  defp put_addresses(body, field, addresses), do: Map.put(body, field, addresses)

  defp base_uri do
    Application.get_env(:bamboo, :sendinblue_base_uri) || default_base_uri()
  end

  defp put_template_params(params, %{private:
    %{templateId: template_name, params: template_model}}) do
    params
    |> Map.put(:templateId, template_name)
    |> Map.put(:params, template_model)
  end

  defp put_template_params(params, _) do
    params
  end

  defp put_tag_params(params, %{private: %{tags: tag}}) do
    Map.put(params, :tags, tag)
  end

  defp put_tag_params(params, _) do
    params
  end

  defp put_attachments(body, %Email{attachments: []}), do: body

  defp put_attachments(body, %Email{attachments: atts}) do
    attachments =
      atts
      |> Enum.map(fn attachment -> prepare_attachment(attachment) end)

    Map.put(body, :attachment, attachments)
  end

  defp prepare_attachment(%Attachment{data: data, filename: filename})
       when not is_nil(data) and not is_nil(filename) do
    %{content: Base.encode64(data), name: filename}
  end

  defp prepare_attachment(%Attachment{path: path, filename: filename} = att)
       when not is_nil(filename) do
    case URI.parse(path) do
      %URI{scheme: nil} ->
        att |> Map.put(:data, File.read!(path)) |> prepare_attachment()

      %URI{} ->
        %{url: path, name: filename}
    end
  end

  defp prepare_attachment(%Attachment{path: path} = att) when not is_nil(path) do
    att |> Map.put(:filename, Path.basename(path)) |> prepare_attachment()
  end

  defp address_map(addresses) when is_list(addresses) do
    addresses
    |> Enum.map(fn
      {nil, address} -> %{email: address}
      {name, address} -> %{email: address, name: name || ""}
      address -> %{email: address}
    end)
  end

  defp address_map(nil) do
    []
  end

  defp default_base_uri, do: "https://api.sendinblue.com"
  defp get_api_url, do: "#{base_uri()}/v3/smtp/email"
end
