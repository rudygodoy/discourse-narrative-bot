module DiscourseNarrativeBot
  class Dice
    def initialize(number_of_dice, range_of_dice)
      @number_of_dice = number_of_dice
      @range_of_dice = range_of_dice
    end

    def roll
      @number_of_dice.times.map { rand(1..@range_of_dice) }
    end
  end
end
