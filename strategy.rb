# Messy, messy code. No time to clean it up.

# This implements a strategy for playing the Kablammo game.

@turn = -1
DIR_OFFSETS = { NORTH => Pixel.new(0, -1), EAST => Pixel.new(1,0), WEST => Pixel.new(-1, 0),
  SOUTH => Pixel.new(0, 1) }
CORNER_OFFSETS = [Pixel.new(1, 1), Pixel.new(1, -1), Pixel.new(-1, 1), Pixel.new(-1, -1)]

@rest_turns = 0
MAX_REST_TURNS = 5

STATE_NORMAL = 1
STATE_HUNTING = 2
@state = STATE_NORMAL
STATE_NAMES = { STATE_NORMAL => "Normal", STATE_HUNTING => "Hunting" }

DIRS = [NORTH, EAST, WEST, SOUTH]
RANDOM_DIRS = DIRS.permutation.to_a

@last_known_opponent_pos = Pixel.new(0, 0)

DEBUG = FALSE

on_turn do
  # Call do_turn so that we can use "return" statements.
  do_turn
end

def setup
end

def get_attackers(pixel)
  opponents.select { |opp| opp.can_fire_at? pixel }
end

def pick_safe_direction()
  DIRS.select do |dir|
    pixel = Pixel.new(robot.x + DIR_OFFSETS[dir].x, robot.y + DIR_OFFSETS[dir].y)
    puts "pick_safe_direction() robot (#{robot.x},#{robot.y}) dir: #{dir} pixel: (#{pixel.x},#{pixel.y}) safe? #{get_attackers(pixel).length == 0} board.available? #{board.available?(pixel)}" if DEBUG
    board.available?(pixel) && get_attackers(pixel).length == 0
  end
end

def flee_or_fight(attackers)
  move = pick_safe_direction()
  unless move.empty?
    move = move[rand move.length]
    puts "flee_or_fight: safe move. moving #{move.inspect}" if DEBUG
    @rest_turns = 0
    return move! move
  end
  move = first_possible_move DIRS
  if move
    puts "flee_or_fight: unsafe move. moving #{move.inspect}" if DEBUG
    @rest_turns = 0
    return move! move
  end
  if robot.ammo == 0
    puts "Recharging under fire." if DEBUG
    @rest_turns += 1
    return rest
  end
  target = attackers.select { |opp| aiming_at? opp }[0]
  unless target.nil?
    puts "flee_or_fight: already aiming at attacker, about to fire" if DEBUG
    @rest_turns = 0
    return fire_at! target
  end
  puts "flee_or_fight: about to aim at attacker" if DEBUG
  @rest_turns = 0
  return aim_at! attackers[0]
end

def can_flee(attacker)
  move = pick_safe_direction()
  puts "can_flee() move: #{move.inspect}" if DEBUG
  !move.empty?
end

def aim_next_to_wall(wall)
  if wall.y > robot.y
    if wall.x != robot.x
      aim_at! Pixel.new(wall.x, wall.y + 1)
    else
      dir = 1
      if @last_known_opponent_pos.x < robot.x
        dir = -1
      elsif @last_known_opponent_pos.x == robot.x
        dir = rand(2) == 1 ? 1 : -1
      end
      aim_at! Pixel.new(wall.x + dir, wall.y)
    end
  elsif wall.y < robot.y
    if wall.x != robot.x
      aim_at! Pixel.new(wall.x, wall.y - 1)
    else
      dir = 1
      if @last_known_opponent_pos.x < robot.x
        dir = -1
      elsif @last_known_opponent_pos.x == robot.x
        dir = rand(2) == 1 ? 1 : -1
      end
      aim_at! Pixel.new(wall.x + dir, wall.y)
    end
  else
    @rest_turns += 1
    rest
  end
end

def do_turn
  @turn += 1
  setup if @turn == 0
  puts "============ Turn #{@turn} ============" if DEBUG

  puts "Robot at (#{robot.x},#{robot.y}), #{STATE_NAMES[@state]} rotation, armor, ammo:  #{robot.rotation} #{robot.armor} #{robot.ammo}, num opponents: #{opponents.length}, num walls: #{board.walls.length}" if DEBUG

  attackers = get_attackers(robot)
  if attackers.length > 1
    @state = STATE_NORMAL
    puts "More than one attacker!" if DEBUG
    @last_known_opponent_pos.x, @last_known_opponent_pos.y = attackers[0].x, attackers[0].y
    return flee_or_fight attackers
  elsif attackers.length == 1
    @state = STATE_NORMAL
    attacker = attackers[0]
    @last_known_opponent_pos.x, @last_known_opponent_pos.y = attacker.x, attacker.y
    puts "One attacker at (#{attacker.x},#{attacker.y}), rotation, armor, ammo:  #{attacker.rotation} #{attacker.armor} #{attacker.ammo}" if DEBUG
    if can_fire_at?(attacker) && robot.ammo > 0
      if can_flee(attacker) && rand(2) == 1
        puts "Can flee safely too. Fleeing" if DEBUG
        return flee_or_fight attackers
      else
        puts "Cannot flee safely." if DEBUG
      end
      puts "Returning fire." if DEBUG
      @rest_turns = 0
      return fire_at! attacker
    end
    return flee_or_fight attackers
  end

  if opponents.length > 0
    @state = STATE_NORMAL
    if robot.ammo > 0
      puts "No attackers, aiming at opponent." if DEBUG
      @rest_turns = 0
      return aim_at! opponents[0]
    end
  end

  unless robot.ammo_full?
    puts "Recharging ammo." if DEBUG
    @state = STATE_NORMAL
    @rest_turns += 1
    return rest
  end
  if @rest_turns >= MAX_REST_TURNS
    @rest_turns = 0
    @state = STATE_HUNTING
  end
  if @state == STATE_HUNTING
    move = first_possible_move RANDOM_DIRS[rand(RANDOM_DIRS.length)]
    if move
      puts "Hunting... moving #{move}" if DEBUG
      return move
    else
      puts "Hunting... no move! Resting." if DEBUG
      return rest
    end
  end
  wall, corner, path = nearest_wall_corner
  puts "nearest_wall_corner: wall: (#{wall.x},#{wall.y}) corner: #{corner.inspect}, path: #{path.inspect}" if DEBUG
  unless corner.nil?
    if path.empty?
      # Choose aim direction
      @rest_turns += 1
      return aim_next_to_wall(wall)
    else
      x, y = path[0]
      puts "Moving from (#{robot.x}, #{robot.y}) toward corner #{corner} thru pixel #{x}, #{y}." if DEBUG
      @rest_turns = 0
      return move_towards! Pixel.new(x, y)
    end
  end
  if @rest_turns > MAX_REST_TURNS
    @rest_turns = 0
    @state = STATE_HUNTING
  end
  puts "Resting." if DEBUG
  @rest_turns += 1
  rest
end

def wall_distances
  return nil if board.walls.empty?
  cells = board.walls.map { |wall| [robot.distance_to(wall), wall] }.sort do |a, b|
    [a[0], a[1].x, a[1].y] <=> [b[0], b[1].x, b[1].y]
  end
  return cells
end

def wall_corners(wall)
  up = Pixel.new(wall.x, wall.y + 1)
  down = Pixel.new(wall.x, wall.y - 1)
  left = Pixel.new(wall.x - 1, wall.y)
  right = Pixel.new(wall.x + 1, wall.y)
  corners = []
  if !board.walls.any? { |w| [w.x, w.y] == [up.x, up.y] } &&
      !board.walls.any? { |w| [w.x, w.y] == [right.x, right.y] }
    corners << Pixel.new(wall.x + 1, wall.y + 1)
  end
  if !board.walls.any? { |w| [w.x, w.y] == [up.x, up.y] } &&
      !board.walls.any? { |w| [w.x, w.y] == [left.x, left.y] }
    corners << Pixel.new(wall.x - 1, wall.y + 1)
  end
  if !board.walls.any? { |w| [w.x, w.y] == [down.x, down.y] } &&
      !board.walls.any? { |w| [w.x, w.y] == [right.x, right.y] }
    corners << Pixel.new(wall.x + 1, wall.y - 1)
  end
  if !board.walls.any? { |w| [w.x, w.y] == [down.x, down.y] } &&
      !board.walls.any? { |w| [w.x, w.y] == [left.x, left.y] }
    corners << Pixel.new(wall.x - 1, wall.y - 1)
  end
  corners.sort { |a,b| robot.distance_to(a) <=> robot.distance_to(b) }
end

def can_navigate_to(corners)
  corners.each do |corner|
    #puts "can_navigate_to: corner: (#{corner.x}, #{corner.y})" if DEBUG
    path = path_to_point(corner)
    return [corner, path] unless path.nil?
  end
  return nil
end

def path_to_point(target)
  path = []
  pixel = Pixel.new(robot.x, robot.y)
  while true
    #puts "path_to_point robot: (#{pixel.x}, #{pixel.y}), target: (#{target.x}, #{target.y}), path: #{path.inspect}" if DEBUG
    return path if (pixel.x == target.x && pixel.y == target.y)
    if target.x < pixel.x
      pixel.x -= 1
      if board.available? pixel
        path << [pixel.x, pixel.y]
        next
      end
      pixel.x += 1
    elsif target.x > pixel.x
      pixel.x += 1
      if board.available? pixel
        path << [pixel.x, pixel.y]
        next
      end
      pixel.x -= 1
    elsif target.y < pixel.y
      pixel.y -= 1
      if board.available? pixel
        path << [pixel.x, pixel.y]
        next
      end
      pixel.y += 1
    elsif target.y > pixel.y
      pixel.y += 1
      if board.available? pixel
        path << [pixel.x, pixel.y]
        next
      end
      return nil
    end
  end
  return nil
end

def nearest_wall_corner
  wall_pairs = wall_distances
  corner_walls = wall_pairs.each do |pair|
    distance, wall = pair
    corners = wall_corners(wall)
    next if corners.empty?
    reachable = can_navigate_to(corners)
    return [wall] + reachable unless reachable.nil?
  end
  return nil
end

def fire_at!(enemy, compensate = 0)
  direction = robot.direction_to(enemy).round
  skew = direction - robot.rotation
  distance = robot.distance_to(enemy)
  max_distance = Math.sqrt(board.height * board.height + board.width * board.width)
  compensation = ( 10 - ( (10 - 3) * (distance / max_distance) ) ).round
  compensation *= -1 if rand(0..1) == 0
  skew += compensation if compensate > rand
  fire! skew
end
