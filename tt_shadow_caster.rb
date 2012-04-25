#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'sketchup.rb'
require 'TT_Lib2/core.rb'

TT::Lib.compatible?('2.6.0', 'TT Shadow Caster')

#-------------------------------------------------------------------------------


module TT::Plugins::ShadowCaster
  
  
  ### CONSTANTS ### ------------------------------------------------------------
  
  # Plugin information
  PLUGIN_ID       = 'TT_ShadowCaster'.freeze
  PLUGIN_NAME     = 'Shadow Caster'.freeze
  PLUGIN_VERSION  = TT::Version.new( 1,0,0 ).freeze
  
  
  ### MENU & TOOLBARS ### ------------------------------------------------------
  
  unless file_loaded?( __FILE__ )
    # Menus
    menu = TT.menu( 'Tools' )
    menu.add_item( 'Shadow Caster' ) { self.cast_shadows }
  end 
  
  
  ### LIB FREDO UPDATER ### ----------------------------------------------------
  
  def self.register_plugin_for_LibFredo6
    {   
      :name => PLUGIN_NAME,
      :author => 'thomthom',
      :version => PLUGIN_VERSION.to_s,
      :date => '07 Feb 12',
      :description => 'Cast shadows to selected faces.',
      :link_info => 'http://forums.sketchucation.com/viewtopic.php?f=323&t=42469'
    }
  end
  
  
  ### MAIN SCRIPT ### ----------------------------------------------------------

  
  # @since 1.0.0
  def self.cast_shadows
    Sketchup.active_model.select_tool( ShadowCasterTool.new )
  end
  
  
  # @since 1.0.0
  class ShadowCasterTool
    
    # @since 1.0.0
    def initialize
      model = Sketchup.active_model
      sel = model.selection
      
      @target = sel[0]
      @plane = @target.plane
      @bounds = @target.bounds
      
      @sun = nil
      @shadow = nil
      
      @rays = []
      @lines = []
      @polygons = []
      @ground = []
    end
    
    # @since 1.0.0
    def resume( view )
      view.invalidate
    end
    
    # @since 1.0.0
    def deactivate( view )
      view.invalidate
    end
    
    # @since 1.0.0
    def onLButtonUp( flags, x, y, view )
      analyse_shadows()
      view.invalidate
    end
    
    # @since 1.0.0
    def onMouseMove( flags, x, y, view )
      view.invalidate
    end
    
    # @since 1.0.0
    def draw( view )
      unless @rays.empty?
        view.line_width = 1
        view.line_stipple = '_'
        view.drawing_color = 'orange'
        view.draw( GL_LINES, @rays )
      end
      
      unless @lines.empty?
        view.line_width = 2
        view.line_stipple = ''
        view.drawing_color = [0,128,0]
        #view.draw( GL_LINES, @lines )
      end
      
      unless @polygons.empty?
        view.line_width = 2
        view.line_stipple = ''
        for polygon in @polygons
          #view.drawing_color = [64,0,128,64]
          #view.draw( GL_POLYGON, polygon )
          
          view.drawing_color = [0,192,0]
          #view.draw( GL_LINE_LOOP, polygon )
        end
      end
    end
    
    # @since 1.0.0
    def analyse_shadows
      model = Sketchup.active_model
      #model.start_operation( 'Cast Shadows', true )
      model.start_operation( 'Cast Shadows', false )
      subcontext = model.entities.select { |e| TT::Instance.is?( e ) }
      @shadow = model.active_entities.add_group
      @shadow.casts_shadows = false
      @shadow.name = 'Shadow'
      @sun = model.shadow_info['SunDirection'].reverse
      @rays.clear
      @lines.clear
      @polygons.clear
      @ground.clear
      cast_shadows( subcontext )
      remove_ground()
      model.commit_operation
    end
    
    # @since 1.0.0
    def cast_shadows( entities, tr = Geom::Transformation.new )
      model = Sketchup.active_model
      for e in entities
        # Ignore entities not contributing shadows.
        next unless e.casts_shadows? && e.visible? && e.layer.visible?
        
        if TT::Instance.is?( e )
          # Recursivly dig into instances.
          t = tr * e.transformation
          d = TT::Instance.definition( e )
          cast_shadows( d.entities, t )
        elsif e.is_a?( Sketchup::Face )
          # Faces on the target plane will subtract from the shadow.
          if polygon = on_plane?( e.outer_loop, tr )
            #e.material = 'orange'
            #e.back_material = 'orange'
            @ground << polygon
            next
          end
          # Calculate the shadow polygon onto the target.
          polygon = project_loop( e.outer_loop, tr )
          @polygons << polygon
          # Check if shadow can hit target.
          bb = Geom::BoundingBox.new
          bb.add( polygon )
          next if @bounds.intersect( bb ).empty?
          # Calculate any holes in the geometry.
          holes = []
          for loop in e.loops
            next if loop.outer?
            holes << project_loop( loop, tr  )
          end
          # Add to the total shadow shape.
          add_shadow( polygon, holes )
        end
      end
    end
    
    # @since 1.0.0
    def project_loop( loop, tr )
      loop.vertices.map { |v|
        pt1 = v.position.transform( tr )
        ray = [ pt1, @sun ]
        pt2 = Geom.intersect_line_plane( ray, @plane )
        projection = pt1.vector_to( pt2 )
        if !projection.valid? || projection.samedirection?( @sun )
          @rays << pt1
          @rays << pt2
        end
        pt2
      }
    end
    
    # @since 1.0.0
    def add_shadow( polygon, holes )
      # Create projected shadow.
      se = @shadow.entities
      
      # Triangulate - as holes in a face tend to cause odd behaviour when
      # exploded / intersected. Faces are added or disappear at random.
      #faces = se.select { |e| e.is_a? ( Sketchup::Face ) }
      #for face in faces
      #  triangulate( face )
      #end
      
      g = se.add_group
      ge = g.entities
      ge.add_face( polygon )
      faces = []
      for hole in holes
        faces << ge.add_face( hole )
      end
      ge.erase_entities( faces )
      # Triangulate - as holes in a face tend to cause odd behaviour when
      # exploded / intersected. Faces are added or disappear at random.
      faces = ge.select { |e| e.is_a? ( Sketchup::Face ) }
      for face in faces
        triangulate( face )
      end
      # Merge with existing shadow.
      tr = Geom::Transformation.new
      gtr = g.transformation
      ge.intersect_with( false, gtr, ge, gtr, true, se.to_a )
      #se.intersect_with( false, tr, se, tr, true, se.to_a ) # (?)
      g.explode
      #se.intersect_with( false, tr, se, tr, true, se.to_a ) # (?)
      # Clean up interior edges.
      edges = se.select { |e|
        if e.is_a?( Sketchup::Edge )
          connected_faces = e.faces.uniq.size
          if e.faces.size != connected_faces
            puts "Edge connected to same face multiple times. ( #{e.faces.inspect} ) #{e}"
          end
          if e.faces.size > 2
            puts "Edge connected to too many faces. ( #{e.faces.inspect} ) #{e}"
          end
          #e.is_a?( Sketchup::Edge ) && e.faces.size != 1
          #connected_faces == 2 || connected_faces == 0
          #connected_faces != 1
          e.faces.size != 1
        else
          false
        end
      }
      edges.each { |e| e.material = 'red' }
      #UI.messagebox('stepping...')
      se.erase_entities( edges )
    end
    
    # @since 1.0.0
    def on_plane?( loop, tr )
      pts = loop.vertices.map { |v|
        v.position.transform( tr )
      }
      if pts.all? { |pt| pt.on_plane?( @plane ) }
        pts
      else
        nil
      end
    end
    
    # @since 1.0.0
    def triangulate( face )
      entities = face.parent.entities
      pm = face.mesh
      for i in (1..pm.count_polygons)
        polygon = pm.polygon_points_at( i )
        begin
          # Some times SketchUp will raise an error saying the points are not
          # planar. It seems to be happening when the points projection cause
          # them to be colinear.
          entities.add_face( polygon )
        rescue
          puts '=== Triangulation Error ==='
          p polygon
          puts "Planar: #{TT::Geom3d.planar_points?(polygon)}"
          puts "Linear: #{linear_points?(polygon)}"
        end
      end
    end
    
    # @since 2.0.0
    def linear_points?(points)
      points = TT::Point3d.extend_all( points )
      points.uniq!
      return false if points.size < 2
      line = points[0,2]
      points.all? { |pt| pt.on_line?( line ) }
    end
    
    # @since 1.0.0
    def remove_ground_shadow( polygon )
      puts 'remove_ground_shadow' 
      se = @shadow.entities
      # Create temp group for intersection.
      # Intersection is required to ensure the geometry splits correctly where
      # the subtraction shape overlaps holes.
      g = se.add_group
      ge = g.entities
      ge.add_face( polygon )
      # Intersect shadow with temp group.
      tr = Geom::Transformation.new
      gtr = g.transformation
      se.intersect_with( false, tr, se, tr, true, g )
      g.erase!
      # Add hole. This so we simply get a reference to the face. 
      hole = se.add_face( polygon )
      hole.material = 'red'
      hole.back_material = 'red'
      hole.erase!
      # Clean up edges.
      edges = se.select { |e|
        e.is_a?( Sketchup::Edge ) && e.faces.size != 1
      }
      edges.each { |e| e.material = 'red' }
      se.erase_entities( edges )
    end
    
    # @since 1.0.0
    def remove_ground
      for polygon in @ground
        remove_ground_shadow( polygon )
      end
    end
    
  end # class ShadowCasterTool

  
  ### DEBUG ### ----------------------------------------------------------------
  
  # @note Debug method to reload the plugin.
  #
  # @example
  #   TT::Plugins::ShadowCaster.reload
  #
  # @since 1.0.0
  def self.reload( tt_lib = false )
    original_verbose = $VERBOSE
    $VERBOSE = nil
    load __FILE__
  ensure
    $VERBOSE = original_verbose
  end

end # module

#-------------------------------------------------------------------------------

file_loaded( __FILE__ )

#-------------------------------------------------------------------------------