class Project {
  final int id;
  final String name;
  final String location;
  final String company;
  final String manager;

  Project({
    required this.id,
    required this.name,
    required this.location,
    required this.company,
    required this.manager,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      location: json['location'] ?? '',
      company: json['company'] ?? '',
      manager: json['manager'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'location': location,
      'company': company,
      'manager': manager,
    };
  }
}