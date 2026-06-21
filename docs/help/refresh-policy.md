# A quick note on refreshing

> The legally-binding version of this lives in the Terms of Service
> ("Data refresh policy" section, web/site/lms/terms.html) — this doc is the
> friendly explainer version, not currently linked anywhere in the app.

**Why the refresh button takes a breather**

You might notice the refresh button on the Scores screen greys out for a minute after you use it, with a little countdown showing when it's ready again. That's deliberate — here's the thinking.

Behind the scenes, live scores are only ever a minute or so fresh anyway. When you hit refresh, the app fetches the latest and then waits before it'll go and ask again — because for that next minute there's genuinely nothing newer to fetch. Tapping again would just hand you the exact same scores while quietly running up the bill for the cloud servers that everyone shares.

So the cooldown isn't us holding data back — it's the app being honest about when there's actually something new to show you. The moment there could be a fresh update, the button lights back up.

**Why a minute is fine for a Last Man Standing game**

LMS isn't a live-betting ticker. What matters is who won each round, and that settles when the matches finish — not second by second. A short delay on scores makes zero difference to your game, while keeping the app fast and cheap to run for everyone playing.

**The league table works the same way, just slower**

You'll see the same thing on the Standings screen, except the table only changes about every half hour rather than every minute. When it's already up to date the refresh button greys out, and the footer shows roughly when pulling again would actually get you newer numbers.

Half an hour might sound like a lot, but it's plenty here. The table is really only used for auto-assign (picking you a team when you don't choose one), and tables are slow to settle anyway — even Googling a score the moment a game ends, it's a coin-flip whether the standings have caught up yet. So there's not much point hammering it, and pulling it more often would just cost more for the same numbers.

**We're keeping an eye on it**

These timings aren't set in stone. I'll be watching real-world usage and the cloud costs and reviewing the balance regularly — if it makes sense to make scores snappier, I will. The goal is simple: keep the app quick and reliable for everyone, without wasting money on fetching the same data twice.

Thanks for playing — and for bearing with the occasional one-minute wait. 🙂
