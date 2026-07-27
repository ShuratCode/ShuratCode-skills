---
name: restaurant-search
description: Find restaurants that are genuinely open at a given time and verifiably serve a meat-free dish or kosher fin fish, by reading real menus. Use for any ask about where to eat or food nearby.
license: MIT
---

# Restaurant Search

Find restaurants that pass three gates, in this order: **in the right area** → **open at the right time** → **menu verifiably contains a qualifying dish**. A restaurant only reaches the final list if all three are confirmed. Never fill gaps with plausible guesses — a wrong "open until 23:00" or an imagined pasta section sends someone on a wasted trip, which is the main failure this skill exists to prevent.

## 1. Read the request

Extract four things. Only ask the user if something is genuinely missing and can't be inferred.

| Input | Default if unstated |
|---|---|
| **Area** | Ask. This is the one thing that can't be guessed. |
| **Time window** | Now → the next ~2 hours |
| **Food filters** | The standard set (below) |
| **Party size / vibe / budget** | Ignore unless mentioned; use to break ties |

**Standard food filters** — a restaurant qualifies if its menu contains at least one dish that is **both** meat-free and one of:
- Fin fish (never shellfish — see the fish rule)
- A vegetarian main (not just a side salad — a dish someone could order as their meal)
- Italian: pasta or pizza, in a meat-free version
- Casual fried sides: french fries, chips, potato wedges

These are defaults, not a fixed rule. If the user names their own criteria ("gluten-free", "just sushi", "somewhere with a garden"), replace the standard set with theirs. If they add to it ("also needs vegan options"), treat the addition as required on top. The diet rule below is the one exception: it stays in force even when the rest of the set is replaced, unless the user explicitly relaxes it.

## 1b. The diet rule

Two constraints, and they apply to every dish recorded as a match. Getting either wrong sends someone to a restaurant where they can't order dinner, which is worse than returning a shorter list.

### No meat

**Fin fish is the only animal flesh that counts.** No pork, beef, veal, lamb, chicken, turkey, duck, game, or cured meat. A pizzeria with twenty pizzas, all of them topped with šunka, pršut or pepperoni, has not passed the Italian filter.

Meat hides in dishes that read as vegetarian. Check for it in:
- **Pasta** — carbonara and amatriciana are pork (pancetta, guanciale); bolognese and ragù are beef. Safe: pomodoro, aglio e olio, quattro formaggi, pesto, arrabbiata, funghi, primavera.
- **Pizza** — capricciosa, quattro stagioni, and anything named for prosciutto/šunka/pepperoni are out. Safe: margherita, funghi, vegetariana, quattro formaggi.
- **Risotto** — frequently built on meat or chicken stock, and *risotto ai frutti di mare* is shellfish. Vegetable and fish risottos are fine when named as such.
- **Salads** — Caesar and most "chef" or "house" salads arrive with chicken or bacon unless the menu says otherwise.
- **Soups and stews** — meat stock is the default. *Riblja čorba* / fish soup is fine if the fish is fin fish.
- **Tortillas, wraps, sandwiches, burgers** — assume chicken or beef unless a vegetarian version is listed.
- **Regional grill staples** — ćevapi, pljeskavica, karađorđeva šnicla, Njeguški steak, kebab, gyros, souvlaki are all meat, however they're described.

In Orthodox countries, a menu section labelled **posno / lean / fasting** is a gift: it's meat-free by definition (usually dairy-free too), and it's where the vegetable mains and fin fish live. Look for it first.

### Fin fish only

The person keeps kosher on fish species. Shellfish never count, no matter how good the restaurant is. **Squid, calamari, octopus, cuttlefish, shrimp, prawns, scampi, langoustine, crab, lobster, mussels, oysters, clams, and scallops all fail the filter.** A menu offering only these has not passed the fish gate — treat it exactly as if it had no fish at all.

**Qualifies** (fins and scales): trout, salmon, sea bass / branzino / brancin, sea bream / orada / dorada, tuna, cod, hake, carp, sardine, anchovy, mackerel, mullet, snapper, halibut, sole, herring, pike, perch.

**Does not qualify, despite being fish**: catfish, eel, shark, monkfish, sturgeon, swordfish, skate, ray — no proper scales.

### Consequences that bite in practice

- **A cuisine label or menu heading proves nothing.** "Seafood restaurant", *frutti di mare*, *morski plodovi*, *mariscos* — read the individual items underneath. In Mediterranean and Adriatic towns these sections are often majority shellfish.
- **Mixed platters don't count.** Fritto misto, seafood platter, mixed grill — built around squid, shrimp or meat, and usually unmodifiable. Only count a platter if the menu separately lists a qualifying portion.
- **"Fish of the day" is not verification.** It's a question to ask when the user calls, not a dish to put in the output.
- **Don't assume a dish can be modified.** "They could leave the pancetta off" is a guess, not a menu item. Only count what's listed.

Record the **dish as written**, so the evidence is checkable: "grilled trout 300g", "pizza funghi", "pasta quattro formaggi". Not "fish", not "vegetarian options available".

A restaurant that fails on fish may still pass on the vegetarian, Italian or fries filter. Re-check it against those before excluding.

## 2. Pin down the actual time

This is where searches quietly go wrong. Resolve the time window **in the restaurant's local timezone**, not the user's. "Open now" for a user in Tel Aviv asking about Lisbon means Lisbon's clock.

Also resolve:
- **Day of week** — Sunday and Monday closures are extremely common, and in many countries so is a mid-afternoon break between lunch and dinner service.
- **Local holidays** — if the date is a public or religious holiday in that country, say so explicitly; posted hours are unreliable and many places close.
- **Last seating** — a kitchen frequently closes 30–60 minutes before the door does. If the user's window ends near closing time, flag it.

State the resolved time once in your answer ("Friday 20:30 local time in Rome") so the user can correct you early.

## 3. Build the candidate list

If a places/maps search tool is available, prefer it — it returns hours, ratings, and coordinates in one shot. Otherwise use web search.

Don't fire one broad query. Decompose, because a single "restaurants in X" returns the same ten tourist traps:

```
"seafood restaurants <area>"
"trattoria <area>" / "pizzeria <area>"
"vegetarian restaurants <area>"
"best restaurants <specific neighborhood>"   ← for each sub-area of a large city
```

For a large or vague area ("north Tel Aviv", "1 hour from London"), break it into named neighborhoods or towns and search each. Aim for **15–25 raw candidates** before filtering — the two gates ahead will remove most of them.

## 4. Gate 1 — opening hours

Check each candidate's hours for the specific day and time. Sources in order of trust: the restaurant's own site → Google Maps/places data → a recent aggregator listing.

- Open at the target time → keep.
- Closed, closed that day, or in a between-services gap → drop, don't mention.
- Hours nowhere to be found → drop from the main list; it can be mentioned in the excluded note.

Watch for stale data: a listing that hasn't been updated in a year, or reviews mentioning permanent closure, means drop it.

## 5. Gate 2 — verify the menu

**Strict verification.** A restaurant makes the final list only if an actual menu or a reliable dish listing confirms a qualifying dish. Look at, in order:

1. The restaurant's own website menu page
2. The menu attached to its Google Maps / places listing
3. A delivery or reservation platform listing its dishes (Wolt, Uber Eats, TheFork, OpenTable, etc.)
4. Recent photos or review text that name specific dishes — weakest source, use only for corroboration

What does **not** count as verification:
- The cuisine label alone. "Italian restaurant" is not proof of pasta on the menu.
- A dish containing meat or shellfish. Check every candidate against the diet rule above before recording it as a match.
- "Vegetarian friendly" or "vegan options" as a listing tag. That's a claim about the restaurant, not a dish. Find the dish.
- Your own prior knowledge of the place.
- A menu that's clearly from a different branch or an obviously outdated season.

If verification fails, the restaurant is **excluded**, no matter how good it looks. Collect these in a short note at the end rather than silently dropping them — "couldn't verify" is useful information, and the user may want to call the place.

Record the specific dish names you found. Those go in the output — they're the evidence.

## 6. Output

Return a ranked list. Rank by how well it matches the request (dish coverage first, then rating, then convenience) — not by rating alone.

Aim for **5–8 restaurants**. If fewer than 3 survive both gates, say so plainly and offer to widen the area, the time window, or the filters, rather than padding the list with unverified places.

Use this structure:

```markdown
**<Area> · <resolved day and local time>** — <N> places open and verified.

### 1. <Name>
<Cuisine> · <price level> · <rating, if known> · <neighborhood>
**Open:** <hours for that day> <flag if kitchen closes early>
**Matched:** <dish names actually found on the menu> — <which filter each satisfies>
**Source:** <where the menu came from>
<One line on why it's worth going: what it's known for, atmosphere, whether to book.>

### 2. ...
```

Then close with:

```markdown
*Not included:* <Name> (closed <day>), <Name> (menu unavailable online — worth calling).
```

Keep dish references to short factual names ("branzino, cacio e pepe, margherita") rather than copying menu descriptions.

If a map display tool is available, offer to plot the results after the list — don't replace the list with a map, since the reasoning is the useful part.

## Worked example

**Request:** "somewhere to eat in Trastevere tonight around 9"

1. Area = Trastevere, Rome. Time = tonight 21:00 Rome time — check what weekday that is locally.
2. Search: `trattoria Trastevere`, `seafood restaurants Trastevere`, `vegetarian Trastevere Rome`, `best restaurants Trastevere` → ~20 candidates.
3. Hours gate: drop the ones closed Mondays and the two that stop seating at 21:00 → 12 left.
4. Menu gate: pull each menu. Keep the one listing grilled branzino by name, the pizzeria with a verified margherita and a vegetarian antipasto, the trattoria with cacio e pepe. The osteria whose only sea dish is fritto misto fails the fish rule — but it also lists melanzane alla parmigiana, so it stays on the vegetarian filter. Drop the trattoria whose entire pasta list is carbonara, amatriciana and ragù. Drop the wine bar whose menu isn't online → 6 left.
5. Output the 6 ranked, each with the qualifying dishes named as written, plus a note listing the wine bar as unverified.

## Common failure modes

- **Counting shellfish as fish.** Squid and shrimp are everywhere on Mediterranean and Adriatic menus and read as "seafood" at a glance. Slipping calamari into the matched-dishes line means the person orders something they can't eat, or drives somewhere for nothing.
- **Missing the meat inside a dish that sounds vegetarian.** Carbonara, capricciosa, Caesar salad, chicken risotto, a "house" wrap. Read the ingredient line, not the dish name.
- **Padding the matched line.** One verified meat-free dish is a pass; listing four dishes when only one qualifies makes the entry look better than it is and hides how thin the options are. If a place has exactly one thing the person can order, say so.
- **Trusting the cuisine tag.** The most frequent source of a bad recommendation is assuming an Italian place has pasta on the menu tonight. Check.
- **Using the user's timezone.** Silently off by hours when the area is abroad.
- **Ignoring the weekly closing day.** Especially in Europe and Israel; check the specific weekday, not "usual hours".
- **Stopping at one search.** One query yields a homogeneous list; several yields real options.
- **Padding to hit a number.** Three verified places beat eight half-checked ones.
