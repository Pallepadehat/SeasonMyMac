import Foundation

/// Little facts about Christmas and winter, one inside every present.
enum SeasonFacts {
    struct Fact: Equatable {
        /// An SF Symbol to go with it.
        let symbol: String
        let text: String
    }

    static let all: [Fact] = [
        Fact(symbol: "snowflake", text: "Snowflakes almost always have six sides. It's down to how water molecules link up as they freeze."),
        Fact(
            symbol: "sun.max",
            text: "Snow isn't really white. Each ice crystal is clear, but together they scatter every colour of light, so a drift looks white."),
        Fact(
            symbol: "camera",
            text: "Wilson \"Snowflake\" Bentley took the first photograph of a single snowflake in 1885, and went on to capture more than 5,000."),
        Fact(
            symbol: "figure.stand",
            text: "The tallest snowman on record, Olympia, stood 37 metres tall in Bethel, Maine, in 2008. Her eyelashes were made from skis."),
        Fact(symbol: "cloud.snow", text: "A snowflake drifting down from a cloud can take around an hour to reach the ground."),
        Fact(
            symbol: "eye",
            text: "Reindeer eyes change colour with the seasons: golden in summer and deep blue in winter, which helps them see in the long Arctic dark."),
        Fact(
            symbol: "pawprint",
            text:
                "Both male and female reindeer grow antlers. Males usually shed theirs in early winter, so reindeer with antlers at Christmas are probably female."
        ),
        Fact(
            symbol: "book.closed",
            text: "Rudolph was dreamed up in 1939 by Robert L. May, for a colouring booklet handed out by the department store Montgomery Ward."),
        Fact(
            symbol: "music.note",
            text: "\"Jingle Bells\" was the first song played in space: in December 1965, the Gemini 6 astronauts played it on a harmonica and bells."),
        Fact(
            symbol: "phone",
            text:
                "NORAD has tracked Santa every Christmas Eve since 1955, after a newspaper ad printed the wrong phone number and children called the air defence hotline."
        ),
        Fact(
            symbol: "leaf",
            text:
                "Every year since 1947, Norway has given London a Christmas tree for Trafalgar Square, as thanks for Britain's help during the Second World War."
        ),
        Fact(
            symbol: "crown",
            text: "Christmas trees took off in Britain after an 1848 picture showed Queen Victoria and Prince Albert around one at Windsor Castle."),
        Fact(symbol: "bird", text: "The first artificial Christmas trees were made in 19th-century Germany, from goose feathers dyed green."),
        Fact(symbol: "sparkles", text: "Tinsel was once made from real strands of silver. It looked lovely, but it tarnished quickly."),
        Fact(
            symbol: "lightbulb",
            text:
                "The first electric Christmas tree lights lit up in 1882, when Edward Johnson, a colleague of Edison, wired 80 red, white and blue bulbs on his tree."
        ),
        Fact(
            symbol: "fork.knife",
            text: "In Japan, many families eat KFC for Christmas dinner, a tradition that began with a 1974 campaign called \"Kentucky for Christmas\"."),
        Fact(
            symbol: "book",
            text: "In Iceland, people give each other books on Christmas Eve and spend the night reading. They call it Jólabókaflóð, the Christmas book flood."),
        Fact(
            symbol: "moon.stars",
            text: "In Iceland, not one but thirteen Yule Lads visit, one each night for the thirteen nights before Christmas, each with his own mischief."),
        Fact(
            symbol: "figure.socialdance",
            text: "In Denmark, families hold hands and dance around the Christmas tree on Christmas Eve, singing carols as they go."),
        Fact(
            symbol: "gift",
            text: "Danish risalamande hides one whole almond. Whoever finds it wins the mandelgave, and some keep it secret to tease everyone else."
        ),
        Fact(symbol: "heart", text: "One of the oldest woven Christmas hearts that still exists was made by Hans Christian Andersen around 1860."),
        Fact(
            symbol: "envelope", text: "The Christmas seal was invented in 1904 by Einar Holbøll, a Danish postal clerk, to raise money for children's health."),
        Fact(symbol: "flame", text: "\"Yule\" comes from the Old Norse jól, which is why Christmas is jul in Danish, Swedish and Norwegian."),
        Fact(symbol: "tv", text: "In Sweden, millions watch the same Donald Duck Christmas special at 3 pm every Christmas Eve, a tradition since 1960."),
        Fact(
            symbol: "music.note.list",
            text: "\"Silent Night\" was first sung on Christmas Eve 1818 in Oberndorf, Austria, and has since been translated into hundreds of languages."),
        Fact(
            symbol: "hand.raised",
            text: "During the Christmas truce of 1914, soldiers on the Western Front stopped fighting, sang carols and in places even played football."),
        Fact(
            symbol: "building.2",
            text: "The Rockefeller Center Christmas tree began in 1931, when construction workers decorated a small tree with paper chains and tin cans."),
        Fact(
            symbol: "calendar",
            text: "The first printed Advent calendars appeared in Germany in the early 1900s. Gerhard Lang is often credited with the first one."),
        Fact(
            symbol: "party.popper",
            text: "Christmas crackers were invented in the 1840s by Tom Smith, a London sweet maker who wanted a fun way to sell his bonbons."),
        Fact(symbol: "music.mic", text: "Bing Crosby's \"White Christmas\" is the best-selling single of all time, with an estimated 50 million copies sold."),
        Fact(
            symbol: "camera.macro", text: "Poinsettias come from Mexico. They're named after Joel Poinsett, who brought them to the United States in the 1820s."
        ),
        Fact(
            symbol: "beach.umbrella", text: "In Australia, Christmas falls in midsummer, so plenty of families celebrate with a barbecue or a day at the beach."
        ),
        Fact(
            symbol: "leaf",
            text: "The \"German\" tradition of hiding a pickle ornament in the tree is almost unknown in Germany. It seems to have started in America."),
        Fact(
            symbol: "house", text: "Gingerbread houses became popular in Germany in the 1800s, around the time the Brothers Grimm published Hansel and Gretel."),
    ]

    /// A random fact, avoiding the ones shown most recently.
    static func next() -> Fact {
        var recent = (UserDefaults.standard.array(forKey: recentKey) as? [Int]) ?? []
        let choices = all.indices.filter { !recent.contains($0) }
        let index = (choices.isEmpty ? Array(all.indices) : choices).randomElement() ?? 0
        recent.append(index)
        UserDefaults.standard.set(Array(recent.suffix(all.count / 2)), forKey: recentKey)
        return all[index]
    }

    private static let recentKey = "recentFacts"
}
