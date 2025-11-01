defmodule MailblocWeb.NotFoundHTML do
  use MailblocWeb, :html

  def render("show.html", assigns) do
    ~H"""
    <section class="py-20 px-4 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl text-center">
        <h1 class="text-4xl sm:text-5xl font-bold tracking-tight text-base-content mb-6">
          You've Hit a Stone Bloc 🧱
        </h1>
        <p class="text-lg text-base-content/70 mb-8">
          This part of the kingdom seems sealed — the scroll (404) you're seeking has vanished behind the castle walls 🏰. Time to ride back!
        </p>
        <a href={~p"/"} class="btn btn-primary btn-lg">
          Return to the Keep
        </a>
      </div>
    </section>
    """
  end
end
