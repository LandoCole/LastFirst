
INSERT INTO topics (slug, label, description) VALUES
  ('politics-policy', 'Politics & Policy', 'Government, elections, legislation, and political analysis'),
  ('world-news', 'World News', 'International affairs, global events, and foreign policy'),
  ('business-economy', 'Business & Economy', 'Markets, finance, entrepreneurship, and economic trends'),
  ('technology', 'Technology', 'Software, hardware, AI, startups, and digital innovation'),
  ('science-climate', 'Science & Climate', 'Scientific research, climate change, environment, and discoveries'),
  ('arts-culture', 'Arts & Culture', 'Visual arts, music, film, theater, and cultural commentary'),
  ('opinion-editorial', 'Opinion & Editorial', 'Commentary, essays, op-eds, and analysis pieces'),
  ('food-cooking', 'Food & Cooking', 'Recipes, restaurant reviews, food culture, and culinary arts'),
  ('health-wellness', 'Health & Wellness', 'Medicine, fitness, mental health, and wellbeing'),
  ('sports', 'Sports', 'Athletics, competitions, teams, and sports analysis'),
  ('real-estate', 'Real Estate', 'Property markets, housing, architecture, and urban development'),
  ('travel', 'Travel', 'Destinations, travel guides, and exploration'),
  ('style-fashion', 'Style & Fashion', 'Fashion trends, design, and personal style'),
  ('classic-literature', 'Classic Literature', 'Literary classics, poetry, and canonical works'),
  ('history', 'History', 'Historical events, figures, and analysis'),
  ('self-help', 'Self Help', 'Personal development, productivity, and life improvement')
ON CONFLICT (slug) DO NOTHING;
;
