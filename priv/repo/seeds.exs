alias TodoTrek.{Accounts, Todos, Scope}

{:ok, user} =
  Accounts.register_user(%{
    email: "user@example.com",
    password: "password password"
  })

scope = Scope.for_user(user)

[home, personal, social] =
  [
    %{title: "Home"},
    %{title: "Personal"},
    %{title: "Social/Professional"}
  ]
  |> Task.async_stream(
    fn list_attrs ->
      {:ok, list} = Todos.create_list(scope, list_attrs)
      list
    end,
    max_concurrency: 3,
    ordered: true,
    timeout: :infinity
  )
  |> Enum.map(fn {:ok, list} -> list end)

personal_task =
  Task.async(fn ->
    # Personal
    [
      "Grocery shopping",
      "Pay bills",
      "Schedule dentist appointment",
      "Meal prep for the week",
      "Update resume",
      "Call mom",
      "Buy birthday gift for friend",
      "Research new recipes",
      "Complete work report",
      "Attend yoga class",
      "Schedule haircut",
      "Start a garden",
      "Update emergency contact list",
      "Buy a new phone charger",
      "Clean out email inbox",
      "Book flights for vacation",
      "Set up a savings account",
      "Review insurance policies",
      "Study for certification exam",
      "Write a letter to a penpal",
      "Update social media profiles",
      "Make dentist appointment for kids",
      "Research new workout routine",
      "Review monthly expenses",
      "Check for any needed vaccinations",
      "Learn to play a new instrument"
    ]
    |> Enum.map(fn title -> %{title: title} end)
    |> then(fn todos ->
      {:ok, _} = Todos.bulk_create_todos(scope, personal.id, todos)
    end)
  end)

home_task =
  Task.async(fn ->
    # Home
    [
      "Pick up dry cleaning",
      "Declutter closet",
      "Get car serviced",
      "Write thank you notes",
      "Water plants",
      "Organize pantry",
      "Backup computer files",
      "Take out trash",
      "Vacuum the house",
      "Change lightbulbs",
      "Mail package at the post office",
      "Organize photos on phone",
      "Write a blog post",
      "Test home security system",
      "Create a weekly cleaning schedule",
      "Buy a new umbrella",
      "Clean windows",
      "Assemble IKEA furniture",
      "Watch a new TV series",
      "Reorganize bookshelf",
      "Purchase new kitchen appliances",
      "Update home inventory",
      "Plan a surprise for a loved one",
      "Organize garage or storage space",
      "Create a digital photo album",
      "Clean out the refrigerator",
      "Visit a museum or art gallery",
      "Schedule a home energy audit",
      "Attend a community event",
      "Organize office or workspace"
    ]
    |> Enum.map(fn title -> %{title: title} end)
    |> then(fn todos ->
      {:ok, _} = Todos.bulk_create_todos(scope, home.id, todos)
    end)
  end)

social_task =
  Task.async(fn ->
    # Social/Professional
    [
      "Plan weekend trip",
      "Walk the dog",
      "Volunteer at local charity",
      "Return library books",
      "Attend networking event",
      "Attend a local meetup",
      "Schedule family photoshoot",
      "Send invites for upcoming party",
      "Attend a concert or theater performance",
      "Make a list of home repairs",
      "Host a game night"
    ]
    |> Enum.map(fn title -> %{title: title} end)
    |> then(fn todos ->
      {:ok, _} = Todos.bulk_create_todos(scope, social.id, todos)
    end)
  end)

Task.await_many([personal_task, home_task, social_task], :infinity)
