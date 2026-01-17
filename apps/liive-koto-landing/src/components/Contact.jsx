import { contactGroups, officeLocations } from '../data/contact';

const Contact = () => (
  <section className="contact">
    <div className="container contact-grid">
      <div className="contact-left">
        <div className="contact-title">Contact</div>
        <div className="contact-links">
          {contactGroups.map((group) => (
            <div key={group.title}>
              <h4>{group.title}</h4>
              <p>{group.description}</p>
              <button type="button">{group.cta}</button>
            </div>
          ))}
        </div>
      </div>
      <div className="contact-right">
        <div className="contact-title">Offices</div>
        <div className="office-grid">
          {officeLocations.map((office) => (
            <div key={office.city} className="office-card">
              <h4>{office.city}</h4>
              <p>{office.detail}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  </section>
);

export default Contact;
