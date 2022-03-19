defmodule Bamboo.SendinBlueHelper do
  @moduledoc """
  Functions for using features specific to SendinBlue's templates.
  """

  alias Bamboo.Email

  @doc """
  Set a single tag for an email that allows you to categorize outgoing emails
  and get detailed statistics.

  A convenience function for `put_private(email, :tag, "my-tag")`

  ## Examples

      tag(email, "welcome-email")

  """
  def tag(email, tag) do
    tags = case Map.get(email.private, :tags) do
      nil -> []
      _ -> Map.get(email.private, :tags)
    end
    email
    |> Email.put_private(:tags, [tag | tags])
  end

  @doc """
  Send emails using SendinBlue's template API.

  Setup SendinBlue to send emails using a template. Use this in conjuction with
  the template content to offload template rendering to SendinBlue. The
  template id specified here must match the template id in SendinBlue.
  SendinBlues's API docs for this can be found [here](https://developers.sendinblue.com/reference/sendtransacemail).

  ## Examples

      template(email, "9746128")
      template(email, "9746128", %{"name" => "Name", "content" => "John"})

  """
  def template(email, template_id, params \\ %{}) do
    email
    |> Email.put_private(:templateId, template_id)
    |> Email.put_private(:params, params)
  end

  @doc """
  Put extra message parameters that are used by SendinBlue. You can set things
  like TrackOpens, TrackLinks or Attachments.

  ## Examples

      put_param(email, "TrackLinks", "HtmlAndText")
      put_param(email, "TrackOpens", true)
      put_param(email, "Attachments", [
        %{
          Name: "file.txt",
          Content: "/some/file.txt" |> File.read!() |> Base.encode64(),
          ContentType: "txt"
        }
      ])

  """
  # def put_param(email, key, value) do
  #   email
  #   |> Email.put_private(:message_params, %{})
  #   |> put_param(key, value)
  # end
  def put_param(%Email{private: %{message_params: _}} = email, key, value) do
    put_in(email.private[:message_params][key], value)
  end
  def put_param(email, key, value) do
    email
    |> Email.put_private(:message_params, %{})
    |> put_param(key, value)
  end
end